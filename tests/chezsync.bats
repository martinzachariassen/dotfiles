#!/usr/bin/env bats
# Behavioural tests for `chezsync`, which orchestrates chezup/chezmirror/chezaudit
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
chezmirror() { echo "CHEZMIRROR"; }
chezaudit()  { echo "CHEZAUDIT"; }
'

@test "chezsync runs chezup then chezmirror, in that order" {
    run zsh -c "$STUBS
$(extract chezsync)
chezsync"
    [ "$status" -eq 0 ]
    [[ "$output" == *CHEZUP* ]]
    [[ "$output" == *CHEZMIRROR* ]]
    # Install before prune: everything before the first CHEZMIRROR must include CHEZUP.
    [[ "${output%%CHEZMIRROR*}" == *CHEZUP* ]]
}

@test "chezsync forwards trailing args to chezup (→ chezmoi apply)" {
    run zsh -c "$STUBS
$(extract chezsync)
chezsync -v"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CHEZUP -v"* ]]
}

@test "chezsync under DRY_RUN previews via chezaudit and never calls chezmirror" {
    run zsh -c "$STUBS
$(extract chezsync)
DRY_RUN=1 chezsync"
    [ "$status" -eq 0 ]
    [[ "$output" == *CHEZUP* ]]
    [[ "$output" == *CHEZAUDIT* ]]
    [[ "$output" != *CHEZMIRROR* ]]
}

@test "chezsync aborts before chezmirror when chezup fails" {
    run zsh -c "$STUBS
$(extract chezsync)
CHEZUP_RC=4 chezsync"
    [ "$status" -eq 4 ]
    [[ "$output" == *CHEZUP* ]]
    [[ "$output" != *CHEZMIRROR* ]]
    [[ "$output" != *CHEZAUDIT* ]]
}
