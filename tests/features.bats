#!/usr/bin/env bats
# Unit tests for scripts/lib/features.sh.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=../scripts/lib/features.sh
    . "$REPO_ROOT/scripts/lib/features.sh"
}

@test "FEATURE_KEYS lists macApps" {
    [ "${#FEATURE_KEYS[@]}" -ge 1 ]
    printf '%s\n' "${FEATURE_KEYS[@]}" | grep -qx macApps
}

@test "feature_default: macApps defaults on" {
    run feature_default macApps
    [ "$output" = "true" ]
}

@test "feature_default: unknown keys default off (opt-in)" {
    run feature_default someNewFeature
    [ "$output" = "false" ]
}
