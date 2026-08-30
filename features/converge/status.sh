#!/usr/bin/env bash
# chezstatus — read-only drift report: file drift and untracked packages, in
# plain language. Never applies, pulls, or removes.

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
    case "${1:-}" in
        -h | --help)
            echo "usage: chezstatus [-v|--verbose] [PATH …]"
            echo "  (no args)   plain-language summary: pending changes, local drift, untracked packages"
            echo "  PATH        raw \`chezmoi diff\` for a file (e.g. chezstatus ~/.zshrc)"
            echo "  -v          raw \`chezmoi diff\` for everything"
            return 0
            ;;
        -v | --verbose)
            shift
            chezmoi diff "$@"
            return
            ;;
        ?*)
            chezmoi diff "$@"
            return
            ;;
    esac

    local status_output
    status_output=$(chezmoi status --exclude scripts 2>&1) || {
        printf '%s\n' "chezstatus: \`chezmoi status\` failed:" >&2
        printf '%s\n' "$status_output" >&2
        return 1
    }
    if [ -z "$status_output" ]; then
        echo "  ✓ in sync — no pending changes, nothing edited locally"
    else
        # right column → "apply would write", left column → "you edited locally".
        local pending drift line col1 col2 path
        pending=""
        drift=""
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            col1=${line:0:1}
            col2=${line:1:1}
            path=${line:3}
            case "$col2" in
                A) pending+="    add      ~/$path"$'\n' ;;
                M) pending+="    modify   ~/$path"$'\n' ;;
                D) pending+="    remove   ~/$path"$'\n' ;;
            esac
            case "$col1" in
                A) drift+="    added    ~/$path"$'\n' ;;
                M) drift+="    edited   ~/$path"$'\n' ;;
                D) drift+="    deleted  ~/$path"$'\n' ;;
            esac
        done <<<"$status_output"

        if [ -n "$pending" ]; then
            echo "── Repo → \$HOME · what \`chezapply\` would write ───────────────"
            printf '%s' "$pending"
            echo
        fi
        if [ -n "$drift" ]; then
            echo "── Local drift · managed files you edited in \$HOME ───────────"
            printf '%s' "$drift"
            echo "  ⚠ \`chezapply\` overwrites these. Keep an edit instead: chezmoi re-add ~/…"
            echo
        fi
    fi

    if command -v brew >/dev/null 2>&1; then
        local removals
        removals=$(brew_removals "$src")
        if [ -n "$removals" ]; then
            echo "── Untracked Homebrew packages (in no active Brewfile tier) ───"
            printf '%s\n' "$removals" | awk -F'\t' '{ printf "  %-8s %s\n", $1, $2 }'
            echo "  reconcile (uninstall): chezmirror"
            echo
        fi
    fi

    echo "  See a file's exact lines:  chezstatus ~/path   ·   all:  chezstatus -v"
    echo "  Apply now:                 chezapply"
}

main "$@"
