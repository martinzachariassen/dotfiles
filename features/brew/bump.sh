#!/usr/bin/env bash
# chez bump — routine dependency upgrade, plus a read-only untracked report.

set -uo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SOURCE_DIR="${DOTFILES_DIR:-$(cd "$_DIR/../.." && pwd)}"

# shellcheck source=../../core/ui.sh
. "$_DIR/../../core/ui.sh"
ui_init_logging
# shellcheck source=lib/removals.sh
. "$_DIR/lib/removals.sh"

main() {
    local src="$SOURCE_DIR"
    echo "── brew update + upgrade ─────────────────────────────────────"
    brew update && brew upgrade
    echo
    echo "── Untracked Homebrew packages (in no Brewfile tier) ──────────"
    local removals
    removals=$(brew_removals "$src")
    if [ -n "$removals" ]; then
        printf '%s\n' "$removals" | awk -F'\t' '{ printf "  %-8s %s\n", $1, $2 }'
        echo "  (reconcile with \`chez mirror\` to uninstall — it prompts per package)"
    else
        echo "  ✓ none — every installed package is tracked"
    fi
    if command -v mise >/dev/null 2>&1; then
        echo
        echo "── mise upgrade (global runtimes) ─────────────────────────────"
        mise upgrade || true
    fi
    echo
    echo "Now: cd $src && git diff   to review, then commit."
}

main "$@"
