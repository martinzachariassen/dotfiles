#!/usr/bin/env bash
# chezreconcile — chezup (install) then chezmirror (remove).
# Untracked *files* are a separate step: chezclean.

set -uo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SOURCE_DIR="${DOTFILES_DIR:-$(cd "$_DIR/../.." && pwd)}"

# shellcheck source=../../core/ui.sh
. "$_DIR/../../core/ui.sh"
ui_init_logging
# shellcheck source=../brew/lib/removals.sh
. "$_DIR/../brew/lib/removals.sh"

main() {
    local src="$SOURCE_DIR"
    explain_titled "Full package reconcile" \
        "Two passes: chezup installs what the Brewfiles declare, then chezmirror" \
        "offers to remove what they don't. Together they make this Mac match the repo."
    bash "$_DIR/up.sh" "$@" || return $?
    echo
    if [ "${DRY_RUN:-}" = 1 ]; then
        echo "── Package removals chezmirror would reconcile (preview) ──────"
        bash "$_DIR/../brew/mirror.sh" -n
        echo "  (DRY_RUN=1 — re-run without it to prune, or run \`chezmirror\`.)"
        return 0
    fi
    echo "── Reconciling package removals (chezmirror) ─────────────────"
    bash "$_DIR/../brew/mirror.sh"
}

main "$@"
