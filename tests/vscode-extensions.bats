#!/usr/bin/env bats
# Pin load-bearing entries in packages/vscode-extensions.txt and guard the
# mirror's negative invariants.
#
# Why this exists:
#   The 03-vscode hook mirrors this file one-to-one onto the machine — anything
#   listed is installed, anything NOT listed is uninstalled on the next apply. So
#   a stray edit here has real teeth: dropping a load-bearing extension would
#   silently uninstall it everywhere, and re-adding an intentionally-dropped one
#   would resurrect it. These tests fail on either.
#
# Scope: load-bearing entries only (extensions the JVM stack, theme, locale
# module, or AI tooling assume). Casual preference extensions are not pinned so
# the tests don't churn on routine edits.

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
@test "lists mermaidchart.vscode-mermaid-chart" { lists mermaidchart.vscode-mermaid-chart; }
@test "lists the Norwegian dictionary (locale module gates install)" {
    # Present unconditionally; the hook/doctor drop it only when locale is off.
    lists streetsidesoftware.code-spell-checker-norwegian-bokmal
}

# ─── Negative invariants: extensions the mirror should prune ────────────────────
# These are ms-python.python extensionPack members. A pack seeds them on install
# but does NOT re-pull them after a manual uninstall, so the mirror removes them
# and they must stay OUT of the manifest (re-adding would re-track them).

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
