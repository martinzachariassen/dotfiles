#!/usr/bin/env bash
# Resolve every formula and cask referenced by every Brewfile module.

set -euo pipefail

SOURCE_DIR="${1:-$(pwd)}"
missing=0

resolve() {
    local kind="$1" name="$2" flag

    if [ "$kind" = "brew" ]; then
        flag="--formula"
    else
        flag="--cask"
    fi

    brew info "$flag" "$name" >/dev/null 2>&1 \
        || brew search "$flag" "$name" 2>/dev/null | grep -Fxq "$name"
}

for f in "$SOURCE_DIR"/Brewfile "$SOURCE_DIR"/brewfiles/Brewfile.*; do
    [ -f "$f" ] || continue
    case "$f" in *.lock.json) continue ;; esac
    echo "── $(basename "$f") ──"
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*tap[[:space:]]+\"([^\"]+)\" ]]; then
            tap="${BASH_REMATCH[1]}"
            brew tap | grep -Fxq "$tap" || brew tap "$tap" >/dev/null
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*(brew|cask)[[:space:]]+\"([^\"]+)\" ]]; then
            kind="${BASH_REMATCH[1]}"
            name="${BASH_REMATCH[2]}"
            resolve "$kind" "$name" \
                || { echo "  ✗ $kind not found: $name"; missing=1; }
        fi
    done < "$f"
done

exit "$missing"
