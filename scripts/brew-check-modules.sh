#!/usr/bin/env bash
# Advisory installed-state check for every Brewfile module.

set +e

SOURCE_DIR="${1:-$(pwd)}"

for f in "$SOURCE_DIR"/Brewfile "$SOURCE_DIR"/Brewfile.*; do
    [ -f "$f" ] || continue
    case "$f" in *.lock.json) continue ;; esac
    echo "── $(basename "$f") ──"
    brew bundle check --verbose --file="$f" || true
done
