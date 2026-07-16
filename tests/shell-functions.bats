#!/usr/bin/env bats
# Tests for shell helper functions defined in the zsh config.
#
# These extract the *real* function definition from the source template and run
# it under zsh, so a regression in the committed definition fails the test —
# rather than re-declaring the function in the test and only checking a copy.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"
    if ! command -v zsh >/dev/null 2>&1; then
        skip "zsh not installed"
    fi
}

# Pull a single-line `name() { ... }` definition out of the template. The line
# carries no Go-template directives, so it is valid shell as-is.
extract_fn() {
    grep -E "^$1\(\) \{" "$ZSHRC" | head -n1
}

# Pull a multi-line `name() { ... }` block (top-level closing brace) out of the
# template. The zellij block carries no Go-template directives either.
extract_fn_block() {
    awk "/^$1\(\) \{/,/^\}/" "$ZSHRC"
}

# Run _zj_pick_session with a stub `zellij` whose list-sessions output is $1
# (empty string ⇒ stub exits 1, mimicking "no sessions"). $2 is the base name.
run_pick_session() {
    local stub_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub_dir"
    if [ -n "$1" ]; then
        printf '#!/bin/sh\nprintf %%s "$STUB_SESSIONS"\n' > "$stub_dir/zellij"
    else
        printf '#!/bin/sh\necho "No active zellij sessions found." >&2\nexit 1\n' > "$stub_dir/zellij"
    fi
    chmod +x "$stub_dir/zellij"
    STUB_SESSIONS="$1" PATH="$stub_dir:$PATH" \
        zsh -c "$(extract_fn_block _zj_pick_session); _zj_pick_session '$2'"
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

@test "_zj_pick_session definition exists in the template" {
    run extract_fn_block _zj_pick_session
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "_zj_pick_session returns base name when no sessions exist" {
    run run_pick_session "" dotfiles
    [ "$status" -eq 0 ]
    [ "$output" = "dotfiles" ]
}

@test "_zj_pick_session suffixes -2 when base session is running" {
    sessions='dotfiles [Created 1m ago]
home [Created 2m ago] (current)
'
    run run_pick_session "$sessions" dotfiles
    [ "$status" -eq 0 ]
    [ "$output" = "dotfiles-2" ]
}

@test "_zj_pick_session resurrects an EXITED base session" {
    sessions='dotfiles [Created 1m ago] (EXITED - attach to resurrect)
home [Created 2m ago] (current)
'
    run run_pick_session "$sessions" dotfiles
    [ "$status" -eq 0 ]
    [ "$output" = "dotfiles" ]
}

@test "_zj_pick_session walks past occupied suffixes" {
    sessions='dotfiles [Created 1m ago]
dotfiles-2 [Created 30s ago]
'
    run run_pick_session "$sessions" dotfiles
    [ "$status" -eq 0 ]
    [ "$output" = "dotfiles-3" ]
}

@test "_zj_pick_session reuses an EXITED suffix before minting a new one" {
    sessions='dotfiles [Created 1m ago]
dotfiles-2 [Created 30s ago] (EXITED - attach to resurrect)
'
    run run_pick_session "$sessions" dotfiles
    [ "$status" -eq 0 ]
    [ "$output" = "dotfiles-2" ]
}

@test "_zj_pick_session leaves an unrelated base name untouched" {
    sessions='dotfiles [Created 1m ago]
'
    run run_pick_session "$sessions" fresh
    [ "$status" -eq 0 ]
    [ "$output" = "fresh" ]
}
