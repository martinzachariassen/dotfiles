#!/usr/bin/env bash
# chez apply — apply without pulling. Flags package drift; never uninstalls.

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
    local status_output response
    explain_titled "Applying config" \
        "Writes this repo's files into your home folder and installs anything" \
        "your profile declares that is missing. Never uninstalls." \
        "Local edits to managed files are overwritten — you get one confirm first."
    status_output=$(chezmoi status --exclude scripts 2>&1)
    if [ -n "$status_output" ]; then
        echo
        echo "── Pending changes ───────────────────────────────────────────"
        echo "$status_output"
        echo "──────────────────────────────────────────────────────────────"
        echo "  What this means:"
        echo "    chezmoi has file changes to apply and/or managed files in \$HOME drifted."
        echo
        echo "  Status codes:"
        echo "    A add   M modify   D remove"
        echo "    left column = your \$HOME edits (drift), right column = repo → \$HOME (apply)"
        echo "    plain-language breakdown: \`chez status\`"
        echo
        echo "  Choices:"
        echo "    y + Enter      apply now with \`chezmoi apply --force\`"
        echo "                   this overwrites drift in managed \$HOME files"
        echo "    n or Enter     abort; inspect first with \`chez status\` (plain) or \`chezmoi diff\` (raw)"
        echo
        printf "Apply these managed dotfile changes now? [y/N] "
        read -r response </dev/tty
        case "$response" in
            [yY] | [yY][eE][sS]) ;;
            *)
                echo "Aborted."
                return 1
                ;;
        esac
    fi
    chezmoi apply --force "$@"
    local rc=$?
    # Flag untracked packages so `chez apply` never silently uninstalls.
    if command -v brew >/dev/null 2>&1; then
        local untracked
        untracked=$(brew_removals "$src")
        if [ -n "$untracked" ]; then
            echo
            echo "  ℹ $(printf '%s\n' "$untracked" | grep -c .) brew package(s) installed locally but declared by no active Brewfile."
            echo "    review: chez status   ·   reconcile (uninstall): chez mirror"
        fi
    fi
    return $rc
}

main "$@"
