#!/usr/bin/env bats
# Unit tests for scripts/bin/wizard.sh pure helpers.
#
# The wizard is sourced with WIZARD_LIB_ONLY=1, which defines its functions and
# loads the module catalog, then returns BEFORE any /dev/tty prompting or apply —
# so these run headless in CI. The interactive flow itself is exercised manually
# via a pty (see the PR notes); here we lock down the drift-prone bits: the prompt
# messages / choices extracted from the template, and the module data readers.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WIZ="$REPO_ROOT/scripts/bin/wizard.sh"
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
}

# The prompt message doubles as a chezmoi --prompt* flag KEY, and a comma in a
# key would be misread by cobra's stringToString. None may contain one.
@test "no prompt message contains a comma" {
    local k
    for k in name email profile signingMode signingKey modules; do
        run wiz "prompt_msg $k"
        [ "$status" -eq 0 ]
        [ -n "$output" ]
        [[ "$output" != *,* ]]
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
    [ "$output" = "claudePersona jvmStack locale macApps macosDefaults theme" ]
    run wiz 'profile_defaults work'
    [ "$output" = "claudePersona jvmStack locale macApps macosDefaults theme cloudAuth" ]
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
    # export so the flag survives the `source` return: bash's `source` is a
    # regular builtin (outside POSIX mode), so a bare `WIZARD_NO_GUM=1 source …`
    # prefix reverts once sourcing finishes and use_gum would miss it — passing
    # only on machines without gum (like CI). export makes the check real.
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

# The pure-bash TUI is the middle tier (first-boot, no gum). Its safety net is
# use_tui: it MUST refuse a dumb/disabled terminal so we fall through to the
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

# Ctrl-C must abort the whole wizard, not fall through: every prompt reads with a
# `read … || fallback`, which also swallows an interrupted read. A SIGINT/SIGTERM
# trap running on_interrupt is what quits cleanly (exit 130), so lock in that it's
# armed and points at the handler.
@test "a SIGINT trap is armed to quit cleanly" {
    run wiz 'declare -F on_interrupt >/dev/null && echo ok'
    [ "$output" = "ok" ]
    run wiz 'trap -p INT'
    [[ "$output" == *on_interrupt* ]]
    run wiz 'trap -p TERM'
    [[ "$output" == *on_interrupt* ]]
}
