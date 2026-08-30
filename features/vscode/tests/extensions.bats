#!/usr/bin/env bats
# Pins load-bearing entries in features/vscode/extensions.txt. The 03-vscode
# hook mirrors this file 1:1 (anything unlisted gets uninstalled), so a stray
# edit has real teeth — only load-bearing extensions are pinned here.

setup() {
    load '../../../core/testing/helper'
    EXT="$REPO_ROOT/features/vscode/extensions.txt"
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

# The whole ms-python pack (python, debugpy, vscode-pylance) was dropped 2026-08 —
# no Python is written on these machines. The pack-member pins that used to live
# here existed only to stop reinstall thrash: ms-python.python declared the other
# two as extensionDependencies, so pruning them made VS Code reseed them on next
# launch. With the parent gone there is nothing left to reseed, so the pins went too.
@test "does NOT list the ms-python pack" {
    not_lists ms-python.python
    not_lists ms-python.debugpy
    not_lists ms-python.vscode-pylance
}

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
