#!/usr/bin/env bats
# Unit tests for scripts/ci/check-commit-msg.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/scripts/ci/check-commit-msg.sh"
    MSG="$BATS_TEST_TMPDIR/msg"
}

write_msg() { printf '%s\n' "$1" >"$MSG"; }

# ─── accepted ──────────────────────────────────────────────────────────────────

@test "accepts a well-formed scoped subject" {
    write_msg "feat(vscode): add healthcheck dictionary entry"
    run bash "$SCRIPT" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts a scopeless subject" {
    write_msg "docs: clarify the install flow"
    run bash "$SCRIPT" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts a breaking-change bang" {
    write_msg "feat(api)!: drop the v1 endpoints"
    run bash "$SCRIPT" "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts a subject of exactly 72 characters" {
    write_msg "feat: $(printf 'x%.0s' {1..66})"
    run bash "$SCRIPT" "$MSG"
    [ "$status" -eq 0 ]
}

# ─── rejected ──────────────────────────────────────────────────────────────────

@test "rejects an unknown type" {
    write_msg "wip: poke at things"
    run bash "$SCRIPT" "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects a missing colon" {
    write_msg "feat add a thing"
    run bash "$SCRIPT" "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects an empty subject after the colon" {
    write_msg "fix: "
    run bash "$SCRIPT" "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects a subject over 72 characters" {
    write_msg "feat: $(printf 'x%.0s' {1..80})"
    run bash "$SCRIPT" "$MSG"
    [ "$status" -ne 0 ]
}

# ─── bypassed ──────────────────────────────────────────────────────────────────

@test "ignores merge commits" {
    write_msg "Merge branch 'main' into feature"
    run bash "$SCRIPT" "$MSG"
    [ "$status" -eq 0 ]
}

@test "ignores fixup commits" {
    write_msg "fixup! feat: something"
    run bash "$SCRIPT" "$MSG"
    [ "$status" -eq 0 ]
}
