#!/usr/bin/env bats
# Pins load-bearing entries in packages/vscode-extensions.txt. The 03-vscode
# hook mirrors this file 1:1 (anything unlisted gets uninstalled), so a stray
# edit has real teeth — only load-bearing extensions are pinned here.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    EXT="$REPO_ROOT/packages/vscode-extensions.txt"
}

# 0 if the manifest lists exactly this ID on its own line (ignores comments).
lists() { grep -Fxq "$1" "$EXT"; }
not_lists() { ! grep -Fxq "$1" "$EXT"; }

@test "manifest exists" { [ -f "$EXT" ]; }

# ─── Load-bearing extensions ───────────────────────────────────────────────────

@test "lists redhat.java (JVM stack)" { lists redhat.java; }
@test "lists anthropic.claude-code" { lists anthropic.claude-code; }
@test "lists the catppuccin theme" { lists catppuccin.catppuccin-vsc; }
@test "lists the Norwegian dictionary (locale module gates install)" {
    # Present unconditionally; the hook/doctor drop it only when locale is off.
    lists streetsidesoftware.code-spell-checker-norwegian-bokmal
}

# ─── Negative invariants: extensions the mirror should prune ────────────────────
# ms-python.python extensionPack members: reseeded by the pack but not re-tracked after removal, so they must stay out of the manifest.

@test "does NOT list ms-python.vscode-pylance" { not_lists ms-python.vscode-pylance; }
@test "does NOT list ms-python.debugpy" { not_lists ms-python.debugpy; }
@test "does NOT list ms-python.vscode-python-envs" { not_lists ms-python.vscode-python-envs; }

# ─── Structural invariants ──────────────────────────────────────────────────────

@test "no duplicate extension IDs" {
    dupes="$(grep -vE '^[[:space:]]*#' "$EXT" | grep -vE '^[[:space:]]*$' | sort | uniq -d)"
    [ -z "$dupes" ]
}

@test "every entry is a lowercase publisher.name id" {
    bad="$(grep -vE '^[[:space:]]*#' "$EXT" |
        grep -vE '^[[:space:]]*$' |
        grep -vE '^[a-z0-9][a-z0-9-]*\.[a-z0-9][a-z0-9._-]*$' || true)"
    [ -z "$bad" ]
}
