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

# ─── ms-python.python pack members ──────────────────────────────────────────────
# Reversal of the #49 decision to let the mirror prune these. Leaving them out
# doesn't prune them, it thrashes: ms-python.python declares both as
# extensionDependencies, so `code --uninstall-extension` refuses, the hook falls
# back to remove_extension_on_disk, and VS Code reseeds them on next launch —
# every apply, forever, re-downloading Pylance each time. Tracking them ends the
# loop and is what the manifest already does for the lldb pair.

@test "lists ms-python.vscode-pylance (pack member; pruning it only thrashes)" {
    lists ms-python.vscode-pylance
}
@test "lists ms-python.debugpy (pack member; pruning it only thrashes)" {
    lists ms-python.debugpy
}

# Not a dependency of ms-python.python — an optional companion the pack does not
# reseed, so the mirror can prune it cleanly. Stays out.
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
