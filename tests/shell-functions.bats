#!/usr/bin/env bats
# Tests for shell helper functions defined in the zsh config.
#
# These extract the *real* function definition from the source template and run
# it under zsh, so a regression in the committed definition fails the test —
# rather than re-declaring the function in the test and only checking a copy.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ZSHRC="$REPO_ROOT/dot_config/zsh/dot_zshrc.tmpl"
    if ! command -v zsh >/dev/null 2>&1; then
        skip "zsh not installed"
    fi
}

# Pull a single-line `name() { ... }` definition out of the template. The line
# carries no Go-template directives, so it is valid shell as-is.
extract_fn() {
    grep -E "^$1\(\) \{" "$ZSHRC" | head -n1
}

@test "mkcd definition exists in the template" {
    run extract_fn mkcd
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "mkcd creates a nested directory and cds into it" {
    fn="$(extract_fn mkcd)"
    tmp="$(mktemp -d)"
    run zsh -c "$fn; cd '$tmp'; mkcd a/b/c; pwd"
    [ "$status" -eq 0 ]
    [ "$output" = "$tmp/a/b/c" ]
    rm -rf "$tmp"
}

@test "mkcd is idempotent on an existing directory" {
    fn="$(extract_fn mkcd)"
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/exists"
    run zsh -c "$fn; cd '$tmp'; mkcd exists; pwd"
    [ "$status" -eq 0 ]
    [ "$output" = "$tmp/exists" ]
    rm -rf "$tmp"
}
