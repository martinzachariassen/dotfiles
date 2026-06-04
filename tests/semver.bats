#!/usr/bin/env bats
# Unit tests for scripts/lib/semver.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=../scripts/lib/semver.sh
    . "$REPO_ROOT/scripts/lib/semver.sh"
}

# ─── semver_extract ────────────────────────────────────────────────────────────

@test "semver_extract pulls version from chezmoi --version output" {
    run semver_extract "chezmoi version v2.52.0, commit abc123, built at 2026"
    [ "$status" -eq 0 ]
    [ "$output" = "2.52.0" ]
}

@test "semver_extract handles a bare version" {
    run semver_extract "2.50.0"
    [ "$output" = "2.50.0" ]
}

@test "semver_extract strips a leading v" {
    run semver_extract "v1.2.3"
    [ "$output" = "1.2.3" ]
}

# ─── semver_lt: true cases ─────────────────────────────────────────────────────

@test "semver_lt: older patch is less" {
    run semver_lt "2.49.9" "2.50.0"
    [ "$status" -eq 0 ]
}

@test "semver_lt: older minor is less" {
    run semver_lt "2.9.0" "2.50.0"
    [ "$status" -eq 0 ]
}

@test "semver_lt: older major is less" {
    run semver_lt "1.99.99" "2.0.0"
    [ "$status" -eq 0 ]
}

@test "semver_lt: shorter version with smaller component" {
    run semver_lt "2.49" "2.50.0"
    [ "$status" -eq 0 ]
}

# ─── semver_lt: false cases ────────────────────────────────────────────────────

@test "semver_lt: equal versions are not less" {
    run semver_lt "2.50.0" "2.50.0"
    [ "$status" -eq 1 ]
}

@test "semver_lt: missing trailing components equal explicit zeros" {
    run semver_lt "2.50" "2.50.0"
    [ "$status" -eq 1 ]
    run semver_lt "2.50.0" "2.50"
    [ "$status" -eq 1 ]
}

@test "semver_lt: newer version is not less" {
    run semver_lt "2.52.0" "2.50.0"
    [ "$status" -eq 1 ]
}

@test "semver_lt: leading zeros are base-10, not octal" {
    run semver_lt "2.08.0" "2.9.0"
    [ "$status" -eq 0 ]
    run semver_lt "2.09.0" "2.08.0"
    [ "$status" -eq 1 ]
}
