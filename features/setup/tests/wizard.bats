#!/usr/bin/env bats
# Unit tests for features/setup/cli.sh pure helpers.
#
# WIZARD_LIB_ONLY=1 sources the wizard's functions and module catalog, then
# returns before any /dev/tty prompting or apply — so these run headless in
# CI. The interactive flow itself is exercised manually via a pty; here we
# lock down the drift-prone bits: prompt messages/choices and module readers.

setup() {
    load '../../../core/testing/helper'
    WIZ="$REPO_ROOT/features/setup/cli.sh"
}

# wiz EXPR — source the helpers in a clean bash and evaluate EXPR; echoes result.
wiz() { bash -c "WIZARD_LIB_ONLY=1 source '$WIZ'; $1"; }

@test "wizard sources cleanly in lib-only mode" {
    run wiz 'true'
    [ "$status" -eq 0 ]
}

@test "prompt_msg reads each prompt's message from the template" {
    run wiz 'prompt_msg name'
    [ "$output" = "Full name for git commits" ]
    run wiz 'prompt_msg email'
    [ "$output" = "Email for git commits" ]
    run wiz 'prompt_msg profile'
    [ "$output" = "Profile" ]
    run wiz 'prompt_msg signingMode'
    [ "$output" = "Git commit signing" ]
    run wiz 'prompt_msg modules'
    [ "$output" = "Optional modules" ]
    run wiz 'prompt_msg corpusRemote'
    [ "$output" = "Corpus backup repo for the distiller (blank for local only)" ]
}

# Every prompted key must be replayed on every non-interactive path, whether or
# not its question was shown. A missing flag drops chezmoi into its raw-mode TUI,
# which cannot run under `curl | bash` — and on the signing path it would silently
# reset the answer.
@test "corpusRemote is replayed by both wizard and signing, unconditionally" {
    grep -q 'prompt_msg corpusRemote' "$REPO_ROOT/features/setup/cli.sh"
    grep -q 'prompt_msg corpusRemote' "$REPO_ROOT/features/sign/cli.sh"
    # Inside the init_flags array literal, not behind an `if`.
    run sed -n '/^init_flags=(/,/^)/p' "$REPO_ROOT/features/setup/cli.sh"
    [[ "$output" == *"prompt_msg corpusRemote"* ]] || return 1
}

# The prompt message doubles as a chezmoi --prompt* flag KEY, and a comma in a
# key would be misread by cobra's stringToString. None may contain one.
@test "no prompt message contains a comma" {
    local k
    for k in name email profile signingMode signingKey modules corpusRemote; do
        run wiz "prompt_msg $k"
        [ "$status" -eq 0 ]
        [ -n "$output" ]
        [[ "$output" != *,* ]] || return 1
    done
}

@test "prompt_choices returns the profile and signing options in order" {
    run wiz 'prompt_choices profile | tr "\n" " "'
    [ "$output" = "personal work minimal " ]
    run wiz 'prompt_choices signingMode | tr "\n" " "'
    [ "$output" = "1password ssh-key off " ]
}

@test "profile_defaults reads [profileDefaults] from modules.toml" {
    run wiz 'profile_defaults personal'
    [ "$output" = "claudeDistiller claudePersona jvmStack locale macApps macosDefaults theme appleDev" ]
    run wiz 'profile_defaults work'
    [ "$output" = "claudeDistiller claudePersona jvmStack locale macApps macosDefaults theme cloudAuth" ]
    run wiz 'profile_defaults minimal'
    [ "$output" = "" ]
}

@test "module catalog loads keys and labels in parallel" {
    run wiz 'echo "${#MOD_KEYS[@]}:${#MOD_LABELS[@]}"'
    [ "$status" -eq 0 ]
    local n="${output%%:*}" m="${output##*:}"
    [ "$n" -gt 0 ]
    [ "$n" = "$m" ]
}

# gum is progressive enhancement: WIZARD_NO_GUM=1 must force the plain-text path
# regardless of whether gum is installed (keeps first-boot + tests deterministic).
@test "use_gum is disabled by WIZARD_NO_GUM" {
    # Must export: a bare `WIZARD_NO_GUM=1 source …` prefix reverts once
    # sourcing finishes, so use_gum would miss it (falsely passing on CI).
    run bash -c "export WIZARD_NO_GUM=1 WIZARD_LIB_ONLY=1; source '$WIZ'; use_gum && echo on || echo off"
    [ "$output" = "off" ]
}

# gum's --selected list is comma-delimited, so every module display line fed to
# the picker MUST be comma-free or pre-selection would split mid-label.
@test "gum module display lines contain no commas" {
    run wiz 'for i in "${!MOD_KEYS[@]}"; do mod_display "$i"; done | grep -c , || true'
    [ "$output" = "0" ]
}

# Each display line must still start with its exact catalog key, since results
# are mapped back to keys by matching these lines.
@test "gum module display lines start with the module key" {
    run wiz 'for i in "${!MOD_KEYS[@]}"; do
                 line="$(mod_display "$i")"; key="${line%% *}"
                 [ "$key" = "${MOD_KEYS[$i]}" ] || { echo "mismatch: $line"; exit 1; }
             done; echo ok'
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

# use_tui must refuse a dumb/disabled terminal so we fall through to the
# numbered menu rather than drawing escape codes into a terminal that can't.
@test "use_tui is disabled by WIZARD_NO_TUI" {
    run bash -c "export WIZARD_LIB_ONLY=1 WIZARD_NO_TUI=1 TERM=xterm; source '$WIZ'; use_tui && echo on || echo off"
    [ "$output" = "off" ]
}

@test "use_tui is disabled on a dumb terminal" {
    run bash -c "export WIZARD_LIB_ONLY=1 TERM=dumb; source '$WIZ'; use_tui && echo on || echo off"
    [ "$output" = "off" ]
}

@test "the bash TUI picker functions are defined" {
    run wiz 'declare -F _tui_read_key _tui_choose _tui_multiselect >/dev/null && echo ok'
    [ "$output" = "ok" ]
}

# Every prompt reads with `read … || fallback`, which also swallows an
# interrupted read — only the SIGINT/SIGTERM trap can quit cleanly (exit 130).
#
# SIGINT is checked only when it is trappable at all. A shell that inherits
# SIGINT already *ignored* cannot trap it — POSIX: a signal ignored on entry
# stays ignored — so `trap … INT` becomes a silent no-op and `trap -p INT`
# prints nothing. bats reaches that state when the suite runs as a set rather
# than a single file, which is how this assertion passed alone and failed in a
# full run. SIGTERM is never inherited-ignored here, so it is checked
# unconditionally and is what actually proves the line ran.
@test "a SIGINT trap is armed to quit cleanly" {
    run wiz 'declare -F on_interrupt >/dev/null && echo ok'
    [ "$output" = "ok" ]
    run wiz 'trap -p TERM'
    [[ "$output" == *on_interrupt* ]] || return 1
    run wiz 'trap -p INT'
    if [ -z "$output" ]; then
        run bash -c 'trap "" INT; bash -c "trap - INT; trap x INT; trap -p INT"'
        [ -z "$output" ] || {
            echo "SIGINT is trappable here, so the wizard should have armed it"
            return 1
        }
        skip "SIGINT is inherited-ignored in this runner; a trap for it cannot be set"
    fi
    [[ "$output" == *on_interrupt* ]] || return 1
}

# Regression: chezmoi has no `apply.force` config key (verified v2.72.0 — it was
# silently ignored), so a handoff without --force stops mid-install on
# "X has changed since chezmoi last wrote it (diff/overwrite/…)?". The wizard's
# own "Apply this setup? [Y/n]" is the only gate a fresh install should show.
@test "every chezmoi handoff passes --force" {
    local all missing
    all="$(grep -c -- '--apply' "$WIZ" || true)"
    missing="$(grep -- '--apply' "$WIZ" | grep -vc -- '--force' || true)"
    [ "$all" -ge 2 ]
    [ "$missing" -eq 0 ]
}

@test "the config template does not claim a force key chezmoi ignores" {
    ! grep -qE '^\s*force\s*=' "$REPO_ROOT/src/.chezmoi.toml.tmpl"
}
