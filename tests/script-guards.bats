#!/usr/bin/env bats
# Pins the "fail loudly if core/ui.sh is missing" guard shared by
# doctor.sh/bootstrap-auth.sh (chezup.sh's copy is covered in chezup.bats),
# so a refactor can't quietly turn the hard failure into a silent `|| true`.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    command -v bash >/dev/null 2>&1 || skip "bash not installed"
    ISO="$(mktemp -d)"
    mkdir -p "$ISO/scripts/bin"  # note: no core/ ⇒ ui.sh is unreachable
}

teardown() { [ -n "${ISO:-}" ] && rm -rf "$ISO"; }

# DOTFILES_DIR is set so doctor's SOURCE_DIR line never falls back to the
# real $HOME/Developer/personal/dotfiles before reaching the guard.
run_isolated() {
    local rel="$1" name
    name="$(basename "$rel")"
    cp "$REPO_ROOT/$rel" "$ISO/scripts/bin/$name"
    run env DOTFILES_DIR="$ISO" bash "$ISO/scripts/bin/$name"
}

@test "doctor.sh fails loudly when core/ui.sh is missing" {
    run_isolated scripts/bin/doctor.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || return 1
    [[ "$output" == *"ui.sh"* ]] || return 1
}

@test "bootstrap-auth.sh fails loudly when core/ui.sh is missing" {
    run_isolated scripts/bin/bootstrap-auth.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || return 1
    [[ "$output" == *"ui.sh"* ]] || return 1
}

@test "wizard.sh fails loudly when core/ui.sh is missing" {
    run_isolated scripts/bin/wizard.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || return 1
    [[ "$output" == *"ui.sh"* ]] || return 1
}

@test "xcode.sh fails loudly when core/ui.sh is missing" {
    run_isolated scripts/bin/xcode.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || return 1
    [[ "$output" == *"ui.sh"* ]] || return 1
}
