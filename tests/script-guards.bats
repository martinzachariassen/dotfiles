#!/usr/bin/env bats
# Pins the "fail loudly if core/ui.sh is missing" guard shared by
# the doctor runner and the feature entry points (up.sh's copy is in converge/tests/up.bats),
# so a refactor can't quietly turn the hard failure into a silent `|| true`.

setup() {
    load '../core/testing/helper'
    skip_unless bash
    ISO="$(mktemp -d)"  # note: no core/ anywhere in it ⇒ ui.sh is unreachable
}

teardown() { [ -n "${ISO:-}" ] && rm -rf "$ISO"; }

# The copy keeps the script's real relative path rather than flattening to its
# basename: every feature's entry point is named cli.sh, so flattening would
# make them collide the moment a second one moves. It also means each script
# resolves core/ from the same depth it really has.
#
# DOTFILES_DIR is set so doctor's SOURCE_DIR line never falls back to the
# real $HOME/Developer/personal/dotfiles before reaching the guard.
run_isolated() {
    local rel="$1"
    mkdir -p "$ISO/$(dirname "$rel")"
    cp "$REPO_ROOT/$rel" "$ISO/$rel"
    run env DOTFILES_DIR="$ISO" bash "$ISO/$rel"
}

@test "doctor/cli.sh fails loudly when core/ui.sh is missing" {
    run_isolated features/doctor/cli.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || return 1
    [[ "$output" == *"ui.sh"* ]] || return 1
}

@test "auth/cli.sh fails loudly when core/ui.sh is missing" {
    run_isolated features/auth/cli.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || return 1
    [[ "$output" == *"ui.sh"* ]] || return 1
}

@test "wizard.sh fails loudly when core/ui.sh is missing" {
    run_isolated features/setup/cli.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || return 1
    [[ "$output" == *"ui.sh"* ]] || return 1
}

@test "xcode.sh fails loudly when core/ui.sh is missing" {
    run_isolated features/xcode/cli.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || return 1
    [[ "$output" == *"ui.sh"* ]] || return 1
}
