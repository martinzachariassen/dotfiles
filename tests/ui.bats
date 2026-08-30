#!/usr/bin/env bats
# core/ui.sh's explain_titled must print exactly what the zsh-native
# _chez_explain in dot_zshrc.tmpl prints.
#
# This matters because the `chez*` verbs are being moved out of that template
# into bash, one feature at a time. `explain` was the obvious candidate to call
# on the way over and is the wrong one — it prints dim lines with no heading.
# These tests are the parity contract, and they exist while both implementations
# do, so a verb that moves cannot quietly change what the user sees.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    UI="$REPO_ROOT/core/ui.sh"
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"
}

# Both sides are run without a TTY, so both strip colour. What is compared is
# the text, the blank line, the glyphs and the two-space gutters.
bash_titled() {
    bash -c '
        . "$1"
        shift
        explain_titled "$@"
    ' _ "$UI" "$@"
}

zsh_titled() {
    local body
    body="$(sed -n '/^_chez_explain() {/,/^}/p' "$ZSHRC")"
    zsh -c "$body
_chez_explain \"\$@\"" _ "$@"
}

@test "explain_titled matches _chez_explain for a title and body" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    local args=("Reconcile packages" "Removes what no Brewfile declares." "Never installs.")
    [ "$(LC_ALL=en_US.UTF-8 bash_titled "${args[@]}")" = "$(LC_ALL=en_US.UTF-8 zsh_titled "${args[@]}")" ]
}

@test "explain_titled matches _chez_explain for a title alone" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    [ "$(LC_ALL=en_US.UTF-8 bash_titled "Just a title")" = "$(LC_ALL=en_US.UTF-8 zsh_titled "Just a title")" ]
}

@test "explain_titled opens with a blank line, then node glyph and title" {
    run env LC_ALL=en_US.UTF-8 bash -c '. "$1"; explain_titled "Title" "body"' _ "$UI"
    [ "$status" -eq 0 ]
    [ -z "${lines[0]:-}" ] || [ "${#lines[@]}" -eq 2 ] # bats strips a leading blank
    [[ "$output" == *"◆  Title"* ]] || return 1
    [[ "$output" == *"│  body"* ]] || return 1
}

@test "explain_titled is silent under QUIET=1" {
    run env QUIET=1 bash -c '. "$1"; explain_titled "Title" "body"' _ "$UI"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# Deliberate divergence from _chez_explain, which hardcodes the Unicode glyphs:
# explain_titled goes through ui_init_glyphs, so a non-UTF-8 locale gets ASCII
# instead of mojibake. Pinned so it is a decision, not an accident.
@test "explain_titled falls back to ASCII glyphs outside UTF-8" {
    run env LC_ALL=C LANG=C LC_CTYPE=C bash -c '. "$1"; explain_titled "Title" "body"' _ "$UI"
    [ "$status" -eq 0 ]
    [[ "$output" == *"*  Title"* ]] || return 1
    [[ "$output" == *"|  body"* ]] || return 1
    [[ "$output" != *"◆"* ]] || return 1
}

@test "explain and explain_titled are different functions" {
    # explain prints dim lines with no heading; a verb moving out of the zshrc
    # that reaches for it silently loses its title.
    run env LC_ALL=en_US.UTF-8 bash -c '. "$1"; ui_init_logging; explain "Title" "body"' _ "$UI"
    [ "$status" -eq 0 ]
    [[ "$output" != *"◆"* ]] || return 1
}
