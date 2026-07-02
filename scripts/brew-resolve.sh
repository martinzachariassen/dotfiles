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

    brew info "$flag" "$name" >/dev/null 2>&1 ||
        brew search "$flag" "$name" 2>/dev/null | grep -Fxq "$name"
}

# check_deprecation KIND NAME — flag packages Homebrew has disabled (won't
# install → hard fail, sets missing=1) or deprecated (still installs → warning so
# a swap can be planned before upstream disables it, as happened with `tldr`).
# Best-effort: needs jq + a JSON payload, silently skips if either is absent.
check_deprecation() {
    local kind="$1" name="$2" flag json node disabled deprecated
    command -v jq >/dev/null 2>&1 || return 0
    if [ "$kind" = "brew" ]; then
        flag="--formula"
        node=".formulae[0]"
    else
        flag="--cask"
        node=".casks[0]"
    fi
    json="$(brew info --json=v2 "$flag" "$name" 2>/dev/null)" || return 0
    [ -n "$json" ] || return 0
    disabled="$(printf '%s' "$json" | jq -r "$node.disabled // false")" || disabled=false
    deprecated="$(printf '%s' "$json" | jq -r "$node.deprecated // false")" || deprecated=false
    if [ "$disabled" = "true" ]; then
        echo "  ✗ $kind disabled by Homebrew (won't install): $name"
        missing=1
    elif [ "$deprecated" = "true" ]; then
        echo "  ! $kind deprecated by Homebrew (plan a swap): $name"
    fi
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
            if resolve "$kind" "$name"; then
                check_deprecation "$kind" "$name"
            else
                echo "  ✗ $kind not found: $name"
                missing=1
            fi
        fi
    done <"$f"
done

exit "$missing"
