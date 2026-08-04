#!/usr/bin/env bats
# Unit tests for scripts/lib/chezmoi-data.sh. CI runs without jq, so these
# exercise the sed fallback; jq-guarded tests below cover the jq path when
# present. Both paths must return identical values.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=../scripts/lib/chezmoi-data.sh
    . "$REPO_ROOT/scripts/lib/chezmoi-data.sh"
    JSON='{"name":"Ada","signingKey":"ssh-ed25519 AAAAkey","profile":"work","useOnePassword":true,"features":{"macApps":false}}'
}

# ─── cm_data_string ────────────────────────────────────────────────────────────

@test "cm_data_string reads a top-level string" {
    run cm_data_string "$JSON" profile
    [ "$output" = "work" ]
}

@test "cm_data_string reads a key with spaces in the value" {
    run cm_data_string "$JSON" signingKey
    [ "$output" = "ssh-ed25519 AAAAkey" ]
}

@test "cm_data_string is empty for a missing key" {
    run cm_data_string "$JSON" nope
    [ "$output" = "" ]
}

# ─── cm_data_bool (the false-reading regression) ───────────────────────────────

@test "cm_data_bool reads a nested feature that is false (not the default)" {
    # jq's `//` treats false as empty, so a disabled feature used to read
    # back as its default.
    run cm_data_bool "$JSON" macApps
    [ "$output" = "false" ]
}

@test "cm_data_bool reads a top-level true" {
    run cm_data_bool "$JSON" useOnePassword
    [ "$output" = "true" ]
}

@test "cm_data_bool is empty for a missing key" {
    run cm_data_bool "$JSON" nope
    [ "$output" = "" ]
}

@test "cm_data_bool sed fallback (no jq on PATH) still reads false" {
    run bash -c 'PATH=/usr/bin:/bin; . "$1/scripts/lib/chezmoi-data.sh"; cm_data_bool "$2" macApps' _ "$REPO_ROOT" "$JSON"
    [ "$output" = "false" ]
}

@test "cm_data_bool jq path also reads false (when jq present)" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    run cm_data_bool "$JSON" macApps
    [ "$output" = "false" ]
}

# ─── cm_toml_string / cm_toml_bool ─────────────────────────────────────────────

@test "cm_toml_string / cm_toml_bool read a chezmoi.toml (BSD+GNU sed)" {
    cfg="$BATS_TEST_TMPDIR/chezmoi.toml"
    printf '[data]\n    profile = "personal"\n    useOnePassword = true\n' >"$cfg"
    run cm_toml_string "$cfg" profile
    [ "$output" = "personal" ]
    run cm_toml_bool "$cfg" useOnePassword
    [ "$output" = "true" ]
}

@test "cm_toml_* are empty for a missing file" {
    run cm_toml_string "$BATS_TEST_TMPDIR/nope.toml" profile
    [ "$output" = "" ]
    run cm_toml_bool "$BATS_TEST_TMPDIR/nope.toml" useOnePassword
    [ "$output" = "" ]
}
