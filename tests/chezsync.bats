#!/usr/bin/env bats
# Behavioural tests for `chezsync`, the two-way package reconcile verb.
#
# chezsync composes three existing verbs — chezup (install direction), chezmirror
# (removal direction) and chezaudit (read-only preview under DRY_RUN). Its own
# logic is just the orchestration: run order, the DRY_RUN preview branch, arg
# passthrough, and fail-fast when the apply step errors. Like the other
# zsh-function suites we EXTRACT the real chezsync body from the committed template
# and run it under zsh, stubbing the composed verbs so a regression in the source
# fails here (we never re-declare a copy of the logic).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
}

# Extract a function body verbatim from the committed template.
extract() {
    sed -n "/^${1}() {/,/^}/p" "$ZSHRC"
}

# chezup/chezmirror/chezaudit stubbed as functions that announce themselves, so we
# can assert which ran (and in what order) with no brew/chezmoi. chezup echoes its
# args (to prove passthrough) and honours CHEZUP_RC (to prove fail-fast).
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
