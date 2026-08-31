#!/usr/bin/env bash
# Advisory installed-state check for every Brewfile module.

set +e

SOURCE_DIR="${1:-$(pwd)}"

for f in "$SOURCE_DIR"/features/brew/Brewfile "$SOURCE_DIR"/features/brew/Brewfile.*; do
    [ -f "$f" ] || continue
    # .template seeds ~/.config/chez/Brewfile.local and declares nothing; see
    # brew-resolve.sh for the same skip.
    case "$f" in *.lock.json | *.template) continue ;; esac
    echo "── $(basename "$f") ──"
    brew bundle check --verbose --file="$f" || true
done
