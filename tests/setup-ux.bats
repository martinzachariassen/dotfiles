#!/usr/bin/env bats
# Guards for the setup UX layer: the step/explain vocabulary in core/ui.sh,
# install.sh's hand-mirrored copy of it (it runs before the repo exists, so it
# cannot source the lib), and the wizard's question headers.
#
# The hard constraint throughout is **bash 3.2** — what a factory-fresh Mac ships.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LOG="$REPO_ROOT/core/ui.sh"
    INSTALL="$REPO_ROOT/install.sh"
    WIZARD="$REPO_ROOT/scripts/bin/wizard.sh"
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"
    BASH32=/bin/bash
}

# ─── log.sh vocabulary ────────────────────────────────────────────────────────

@test "explain prints its lines by default" {
    run bash -c ". '$LOG'; ui_init_logging; explain 'hello there'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello there"* ]]
}

@test "QUIET=1 suppresses explain but leaves results" {
    run bash -c ". '$LOG'; ui_init_logging; QUIET=1 explain 'noise'; ok 'result'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"noise"* ]]
    [[ "$output" == *"result"* ]]
}

@test "a suppressed explain cannot trip set -e" {
    run bash -c "set -e; . '$LOG'; ui_init_logging; QUIET=1; f() { explain 'x'; }; f; echo REACHED"
    [ "$status" -eq 0 ]
    [[ "$output" == *"REACHED"* ]]
}

@test "explain works under ui_init_status as well as ui_init_logging" {
    run bash -c ". '$LOG'; ui_init_status; explain 'flat line'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"flat line"* ]]
}

@test "ui_elapsed stays silent for fast steps and formats slow ones" {
    # Under 3s prints nothing, so quick runs don't grow a pointless "(0s)".
    run bash -c ". '$LOG'; ui_init_logging; printf '[%s]' \"\$(ui_elapsed \$(ui_now))\""
    [ "$output" = "[]" ]
    run bash -c ". '$LOG'; ui_init_logging; printf '[%s]' \"\$(ui_elapsed \$(( \$(ui_now) - 372 )))\""
    [ "$output" = "[6m12s]" ]
    run bash -c ". '$LOG'; ui_init_logging; printf '[%s]' \"\$(ui_elapsed \$(( \$(ui_now) - 45 )))\""
    [ "$output" = "[45s]" ]
}

@test "step_begin numbers each step out of the declared total" {
    run bash -c ". '$LOG'; ui_init_steps 3; step_begin One; step_begin Two"
    [[ "$output" == *"[1/3]"* ]]
    [[ "$output" == *"[2/3]"* ]]
}

# ─── bash 3.2 compatibility ───────────────────────────────────────────────────

@test "the setup scripts run under bash 3.2" {
    "$BASH32" --version | head -1 | grep -q 'version 3\.2' || skip "/bin/bash is not 3.2"
    "$BASH32" -n "$INSTALL"
    "$BASH32" -n "$WIZARD"
    "$BASH32" -c ". '$LOG'; ui_init_steps 2; step_begin X; explain 'y'" >/dev/null
}

@test "no printf \\u escapes anywhere — bash 3.2 prints them literally" {
    # bash 3.2's printf has no \uXXXX; such an escape would render as raw text
    # on exactly the fresh Mac this bootstrap targets.
    ! grep -rn 'printf.*\\u[0-9a-fA-F]\{4\}' \
        "$REPO_ROOT/scripts" "$INSTALL" "$REPO_ROOT/src/dot_config/zsh"
}

@test "SUB_MARK has an ASCII fallback for non-UTF-8 locales" {
    run bash -c ". '$LOG'; LC_ALL=C LANG=C LC_CTYPE=C ui_init_glyphs; printf '%s' \"\$SUB_MARK\""
    [ -n "$output" ]
    # Must be pure ASCII, or a dumb terminal shows mojibake.
    [[ "$output" =~ ^[[:print:]]+$ ]]
    run bash -c ". '$LOG'; LC_ALL=en_US.UTF-8 ui_init_glyphs; printf '%s' \"\$SUB_MARK\""
    [ "$output" = "↳" ]
}

# ─── install.sh ───────────────────────────────────────────────────────────────

@test "install.sh states its step count and never sources the repo lib" {
    grep -q 'STEP_TOTAL=5' "$INSTALL"
    # It runs via curl|bash before the clone exists — sourcing would break it.
    ! grep -qE '^\s*\.\s+.*scripts/lib/' "$INSTALL"
}

@test "install.sh explains each step before doing it" {
    for topic in 'Xcode Command Line Tools' 'Homebrew' 'chezmoi' 'Dotfiles repo' 'Setup wizard'; do
        grep -qF "step \"$topic\"" "$INSTALL"
    done
    grep -q 'Roughly 15-25 minutes' "$INSTALL"
    grep -q 'safe to re-run' "$INSTALL"
}

@test "install.sh ticks visibly while waiting on Apple's GUI installer" {
    # A silent 30-minute poll is indistinguishable from a hung script.
    grep -q "waiting for Apple" "$INSTALL"
}

@test "install.sh honours QUIET=1" {
    grep -q 'QUIET:-0' "$INSTALL"
}

# ─── wizard ───────────────────────────────────────────────────────────────────

@test "the wizard's step counter matches the number of questions it asks" {
    local total asked
    total="$(sed -nE 's/^QTOTAL=([0-9]+).*/\1/p' "$WIZARD" | head -1)"
    asked="$(grep -c '^ask_step ' "$WIZARD")"
    [ -n "$total" ]
    [ "$total" -eq "$asked" ]
}

@test "the wizard says answers are changeable later" {
    grep -qF 'chezsetup' "$WIZARD"
    grep -q 'Nothing is permanent' "$WIZARD"
}

@test "the wizard explains what applying will do before the confirm" {
    grep -q 'Saying yes will' "$WIZARD"
    grep -q 'never uninstalls' "$WIZARD"
}

@test "ask_sub renders without its own number" {
    grep -q '^ask_sub()' "$WIZARD"
    grep -q 'SUB_MARK' "$WIZARD"
}

# ─── zsh verbs ────────────────────────────────────────────────────────────────

@test "zshrc defines _chez_explain and honours QUIET" {
    grep -q '^_chez_explain() {' "$ZSHRC"
    sed -n '/^_chez_explain() {/,/^}/p' "$ZSHRC" | grep -q 'QUIET'
}

@test "the destructive verbs explain themselves before acting" {
    sed -n '/^chezmirror() {/,/^}/p' "$ZSHRC" | grep -q '_chez_explain'
    sed -n '/^chezapply() {/,/^}/p' "$ZSHRC" | grep -q '_chez_explain'
    sed -n '/^chezreconcile() {/,/^}/p' "$ZSHRC" | grep -q '_chez_explain'
}

@test "chezhelp documents the QUIET knob" {
    sed -n '/^chezhelp() {/,/^}/p' "$ZSHRC" | grep -q 'QUIET=1'
}
