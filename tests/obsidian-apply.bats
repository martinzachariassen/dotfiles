#!/usr/bin/env bats
# Unit tests for the pure helpers in scripts/lib/obsidian-apply.sh.
#
# Scope: obsidian_find_vault — the only helper that doesn't hit the network
# (theme/plugin downloads via curl) or the live filesystem of an actual vault
# (the seed_* helpers). Those are exercised end-to-end via DRY_RUN in the
# 02d-obsidian-apply.sh.tmpl pathway and aren't unit-testable without major
# refactoring.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not installed — obsidian_find_vault needs it"
    fi
    # shellcheck source=../scripts/lib/obsidian-apply.sh
    . "$REPO_ROOT/scripts/lib/obsidian-apply.sh"
    OB_REGISTRY="$BATS_TEST_TMPDIR/obsidian.json"
}

# ─── Missing / empty / malformed inputs return nothing ─────────────────────

@test "obsidian_find_vault returns empty when registry file is missing" {
    rm -f "$OB_REGISTRY"
    run obsidian_find_vault
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "obsidian_find_vault returns empty when JSON is malformed" {
    printf '%s' '{ not json' > "$OB_REGISTRY"
    run obsidian_find_vault
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "obsidian_find_vault returns empty when vaults key is absent" {
    printf '%s' '{"other": "stuff"}' > "$OB_REGISTRY"
    run obsidian_find_vault
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "obsidian_find_vault returns empty when vaults is an empty object" {
    printf '%s' '{"vaults": {}}' > "$OB_REGISTRY"
    run obsidian_find_vault
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── Single vault: returned regardless of open flag ────────────────────────

@test "obsidian_find_vault returns the only vault when open is absent" {
    printf '%s' '{"vaults": {"abc": {"path": "/my/vault"}}}' > "$OB_REGISTRY"
    run obsidian_find_vault
    [ "$status" -eq 0 ]
    [ "$output" = "/my/vault" ]
}

@test "obsidian_find_vault returns the only vault when open is true" {
    printf '%s' '{"vaults": {"abc": {"path": "/my/vault", "open": true}}}' > "$OB_REGISTRY"
    run obsidian_find_vault
    [ "$output" = "/my/vault" ]
}

# ─── Multiple vaults: open=true wins; otherwise first ──────────────────────

@test "obsidian_find_vault prefers the vault flagged open=true" {
    # The open vault is listed second to verify the iteration prefers
    # open=true over insertion order.
    cat > "$OB_REGISTRY" <<'JSON'
{
    "vaults": {
        "first":  {"path": "/v1", "open": false},
        "second": {"path": "/v2", "open": true}
    }
}
JSON
    run obsidian_find_vault
    [ "$output" = "/v2" ]
}

@test "obsidian_find_vault falls back to first vault when none are open" {
    cat > "$OB_REGISTRY" <<'JSON'
{
    "vaults": {
        "first":  {"path": "/v1", "open": false},
        "second": {"path": "/v2", "open": false}
    }
}
JSON
    run obsidian_find_vault
    [ "$output" = "/v1" ]
}

@test "obsidian_find_vault tolerates a vault entry without a path" {
    # Defensive: a corrupt registry entry should not crash the apply.
    cat > "$OB_REGISTRY" <<'JSON'
{"vaults": {"abc": {"open": true}}}
JSON
    run obsidian_find_vault
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
