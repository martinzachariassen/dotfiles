#!/usr/bin/env bash
# The VS Code extension mirror: install everything the manifest lists, uninstall
# everything it does not.
#
# Invoked by run_onchange_after_03-vscode.sh.tmpl, which keeps the darwin guard
# and resolves the module-gated exclusions — those are render-time decisions and
# cannot be made here, so they arrive as arguments.

set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
EXTENSIONS_FILE="$_DIR/extensions.txt"
EXTENSIONS_DIR="${VSCODE_EXTENSIONS_DIR:-$HOME/.vscode/extensions}"

# shellcheck source=lib.sh
. "$_DIR/lib.sh"

if ! command -v code >/dev/null 2>&1; then
    echo "! VS Code CLI not found; extension sync skipped — re-runs automatically"
    echo "  on the next \`chez up\`/\`chez apply\` once brew bundle has installed it"
    exit 0
fi

if [ ! -f "$EXTENSIONS_FILE" ]; then
    echo "! VS Code extension manifest missing: $EXTENSIONS_FILE"
    exit 0
fi

installed_extensions() {
    code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' || true
}

# One manifest drives both install and prune; excluding off-module entries keeps
# them consistent.
MANIFEST="$(vscode_read_manifest "$EXTENSIONS_FILE" "$@")"

install_marketplace_extensions() {
    local installed ext
    installed="$(installed_extensions)"
    while IFS= read -r ext || [ -n "$ext" ]; do
        [ -n "$ext" ] || continue
        if printf '%s\n' "$installed" | grep -qxF "$ext"; then
            echo "✓ extension already installed: $ext"
        else
            echo "→ installing extension: $ext"
            # Continue-on-error: one bad ID mustn't abort the rest.
            code --install-extension "$ext" || echo "  ! failed to install: $ext (continuing)"
        fi
    done <<EOF
$MANIFEST
EOF
}

# Fallback for extension packs the CLI refuses to uninstall (external dependents).
remove_extension_on_disk() {
    local ext="$1" changed=false dir cache

    shopt -s nullglob nocaseglob
    for dir in "$EXTENSIONS_DIR/$ext"-*; do
        [ -d "$dir" ] || continue
        rm -rf "$dir" && changed=true
    done
    shopt -u nullglob nocaseglob

    cache="$EXTENSIONS_DIR/extensions.json"
    if [ -f "$cache" ] && command -v python3 >/dev/null 2>&1; then
        # The heredoc is its own statement rather than an `if` condition, because
        # shfmt has no stable opinion about `if cmd <<'EOF'; then`: 3.14 wants
        # `then` on its own line after the terminator and older builds want it on
        # the opening line, so a local run and CI disagree forever depending on
        # which one each has. Splitting it sidesteps the construct entirely.
        pruned=0
        python3 - "$cache" "$ext" <<'PY' || pruned=1
import json, sys
cache, ext = sys.argv[1], sys.argv[2].lower()
try:
    data = json.load(open(cache))
except Exception:
    sys.exit(1)
kept = [e for e in data if e.get("identifier", {}).get("id", "").lower() != ext]
if len(kept) == len(data):
    sys.exit(1)  # nothing pruned
json.dump(kept, open(cache, "w"))
PY
        if [ "$pruned" -eq 0 ]; then
            changed=true
        fi
    fi

    [ "$changed" = true ]
}

prune_untracked_extensions() {
    local installed untracked ext
    installed="$(installed_extensions)"
    untracked="$(vscode_untracked "$installed" "$MANIFEST")"
    [ -n "$untracked" ] || return 0

    while IFS= read -r ext || [ -n "$ext" ]; do
        [ -n "$ext" ] || continue
        echo "→ uninstalling untracked extension: $ext"
        if code --uninstall-extension "$ext" >/dev/null 2>&1; then
            continue
        fi
        if remove_extension_on_disk "$ext"; then
            echo "  ↳ CLI declined; removed on disk instead"
        else
            echo "  ! failed to uninstall: $ext (continuing)"
        fi
    done <<EOF
$untracked
EOF
}

echo "▶ VS Code extensions"
echo "  Manifest: $EXTENSIONS_FILE"

install_marketplace_extensions
prune_untracked_extensions

echo "✓ VS Code extensions mirror the manifest"
