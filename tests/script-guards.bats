#!/usr/bin/env bats
# The shared "fail loudly if the sibling log.sh is missing" guard, pinned for
# every report/apply script that carries it (doctor.sh, bootstrap-auth.sh — the
# chezup.sh copy of this guard is exercised in chezup.bats).
#
# Why this exists:
#   Each of these scripts sources scripts/lib/log.sh via a script-relative path
#   and, if it can't be read, prints "<script>: missing …/log.sh" and exits 1
#   rather than limping on with undefined colour/glyph helpers. A refactor that
#   turned that hard failure into a silent `|| true` would leave a broken
#   checkout printing garbage instead of a clear error, so we lock it down by
#   running each script from a copy that deliberately lacks the lib/ sibling.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    command -v bash >/dev/null 2>&1 || skip "bash not installed"
    ISO="$(mktemp -d)"
    mkdir -p "$ISO/scripts/bin"  # note: no scripts/lib ⇒ log.sh is unreachable
}

teardown() { [ -n "${ISO:-}" ] && rm -rf "$ISO"; }

# run_isolated SCRIPT_REL — copy the named script into the lib-less tree and run
# it. DOTFILES_DIR is set so bootstrap-auth's SOURCE_DIR line never shells out to
# chezmoi before reaching the guard.
run_isolated() {
    local rel="$1" name
    name="$(basename "$rel")"
    cp "$REPO_ROOT/$rel" "$ISO/scripts/bin/$name"
    run env DOTFILES_DIR="$ISO" bash "$ISO/scripts/bin/$name"
}

@test "doctor.sh fails loudly when log.sh is missing" {
    run_isolated scripts/bin/doctor.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]]
    [[ "$output" == *"log.sh"* ]]
}

@test "bootstrap-auth.sh fails loudly when log.sh is missing" {
    run_isolated scripts/bin/bootstrap-auth.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]]
    [[ "$output" == *"log.sh"* ]]
}
