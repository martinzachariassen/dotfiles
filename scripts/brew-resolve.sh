#!/usr/bin/env bash
# Resolve every formula and cask referenced by every Brewfile module.

set -euo pipefail

SOURCE_DIR="${1:-$(pwd)}"
missing=0

for f in "$SOURCE_DIR"/Brewfile "$SOURCE_DIR"/brewfiles/Brewfile.*; do
    [ -f "$f" ] || continue
    case "$f" in *.lock.json) continue ;; esac
    echo "── $(basename "$f") ──"
    while read -r line; do
        name="$(echo "$line" | sed -E 's/^(brew|cask) "([^"]+)".*/\2/')"
        kind="$(echo "$line" | awk '{print $1}')"
        if [ "$kind" = "brew" ]; then
            brew info --formula "$name" >/dev/null 2>&1 \
                || { echo "  ✗ formula not found: $name"; missing=1; }
        else
            brew info --cask "$name" >/dev/null 2>&1 \
                || { echo "  ✗ cask not found: $name"; missing=1; }
        fi
    done < <(grep -E '^(brew|cask) "' "$f" || true)
done

exit "$missing"
