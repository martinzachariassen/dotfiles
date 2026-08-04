#!/usr/bin/env bats
# Tests for shell helper functions defined in the zsh config. Extracts the real
# definition from the source template and runs it under zsh, rather than
# re-declaring a copy, so a regression in the committed code fails here.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"
    if ! command -v zsh >/dev/null 2>&1; then
        skip "zsh not installed"
    fi
}

# No Go-template directives on this line, so it's valid shell as-is.
extract_fn() {
    grep -E "^$1\(\) \{" "$ZSHRC" | head -n1
}

# The zellij block carries no Go-template directives either, so it's valid
# shell as-is.
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

@test "_zj_pick_session skips an EXITED base session (never resurrects)" {
    sessions='dotfiles [Created 1m ago] (EXITED - attach to resurrect)
home [Created 2m ago] (current)
'
    run run_pick_session "$sessions" dotfiles
    [ "$status" -eq 0 ]
    [ "$output" = "dotfiles-2" ]
}

@test "_zj_pick_session walks past occupied suffixes" {
    sessions='dotfiles [Created 1m ago]
dotfiles-2 [Created 30s ago]
'
    run run_pick_session "$sessions" dotfiles
    [ "$status" -eq 0 ]
    [ "$output" = "dotfiles-3" ]
}

@test "_zj_pick_session skips an EXITED suffix instead of reusing it" {
    sessions='dotfiles [Created 1m ago]
dotfiles-2 [Created 30s ago] (EXITED - attach to resurrect)
'
    run run_pick_session "$sessions" dotfiles
    [ "$status" -eq 0 ]
    [ "$output" = "dotfiles-3" ]
}

@test "_zj_pick_session leaves an unrelated base name untouched" {
    sessions='dotfiles [Created 1m ago]
'
    run run_pick_session "$sessions" fresh
    [ "$status" -eq 0 ]
    [ "$output" = "fresh" ]
}

# Run _zj_session_name (no arg) with cwd $1 and a stub `git` whose
# rev-parse --show-toplevel prints $2 (empty ⇒ stub exits 1, i.e. "not a repo").
run_session_name() {
    local stub_dir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$stub_dir"
    if [ -n "$2" ]; then
        printf '#!/bin/sh\nprintf %%s "$STUB_TOPLEVEL"\n' > "$stub_dir/git"
    else
        printf '#!/bin/sh\nexit 1\n' > "$stub_dir/git"
    fi
    chmod +x "$stub_dir/git"
    STUB_TOPLEVEL="$2" PATH="$stub_dir:$PATH" \
        zsh -c "cd '$1'; $(extract_fn_block _zj_session_name); _zj_session_name"
}

@test "_zj_session_name definition exists in the template" {
    run extract_fn_block _zj_session_name
    [ "$status" -eq 0 ]
    [[ "$output" == *"_zj_session_name() {"* ]]
}

@test "_zj_session_name uses the git repo root name from any subdir" {
    mkdir -p "$BATS_TEST_TMPDIR/Proj/sub/dir"
    run run_session_name "$BATS_TEST_TMPDIR/Proj/sub/dir" "$BATS_TEST_TMPDIR/Proj"
    [ "$status" -eq 0 ]
    [ "$output" = "proj" ]
}

@test "_zj_session_name falls back to \$HOME → home outside a repo" {
    run run_session_name "$HOME" ""
    [ "$status" -eq 0 ]
    [ "$output" = "home" ]
}

@test "_zj_session_name falls back to cwd basename outside a repo" {
    mkdir -p "$BATS_TEST_TMPDIR/Some Dir"
    run run_session_name "$BATS_TEST_TMPDIR/Some Dir" ""
    [ "$status" -eq 0 ]
    [ "$output" = "some-dir" ]
}

@test "_zj_session_name honors an explicit argument over the repo root" {
    run zsh -c "$(extract_fn_block _zj_session_name); _zj_session_name 'My Name'"
    [ "$status" -eq 0 ]
    [ "$output" = "my-name" ]
}
