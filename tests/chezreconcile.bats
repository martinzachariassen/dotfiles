#!/usr/bin/env bats
# Behavioural tests for `chezreconcile`, which orchestrates chezup/chezmirror
# (install, removal, DRY_RUN preview). Extracts the real body from the committed
# template and runs it under zsh with the composed verbs stubbed.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
}

extract() {
    sed -n "/^${1}() {/,/^}/p" "$ZSHRC"
}

# Stubs announce themselves so run order is assertable without brew/chezmoi;
# chezup echoes its args (passthrough) and honors CHEZUP_RC (fail-fast).
STUBS='
chezup()     { echo "CHEZUP $*"; return ${CHEZUP_RC:-0}; }
chezmirror() { echo "CHEZMIRROR $*"; }
'

@test "chezreconcile runs chezup then chezmirror, in that order" {
    run zsh -c "$STUBS
$(extract chezreconcile)
chezreconcile"
    [ "$status" -eq 0 ]
    [[ "$output" == *CHEZUP* ]] || return 1
    [[ "$output" == *CHEZMIRROR* ]] || return 1
    # Install before prune: everything before the first CHEZMIRROR must include CHEZUP.
    [[ "${output%%CHEZMIRROR*}" == *CHEZUP* ]] || return 1
}

@test "chezreconcile forwards trailing args to chezup (→ chezmoi apply)" {
    run zsh -c "$STUBS
$(extract chezreconcile)
chezreconcile -v"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CHEZUP -v"* ]] || return 1
}

@test "chezreconcile under DRY_RUN previews via chezmirror -n and never removes" {
    run zsh -c "$STUBS
$(extract chezreconcile)
DRY_RUN=1 chezreconcile"
    [ "$status" -eq 0 ]
    [[ "$output" == *CHEZUP* ]] || return 1
    [[ "$output" == *"CHEZMIRROR -n"* ]] || return 1
}

@test "chezreconcile aborts before chezmirror when chezup fails" {
    run zsh -c "$STUBS
$(extract chezreconcile)
CHEZUP_RC=4 chezreconcile"
    [ "$status" -eq 4 ]
    [[ "$output" == *CHEZUP* ]] || return 1
    [[ "$output" != *CHEZMIRROR* ]] || return 1
}
