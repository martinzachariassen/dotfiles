#!/usr/bin/env bash
# chez setup — change this Mac's saved setup answers.
#
# Default fills in newly added keys only, keeping every existing answer.
# --reset/-r sets the machine up as new: it clears chezmoi's run-once state so
# every hook fires again, re-asks the full wizard, then applies.

set -uo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SOURCE_DIR="${DOTFILES_DIR:-$(cd "$_DIR/../.." && pwd)}"

# shellcheck source=../../core/ui.sh
. "$_DIR/../../core/ui.sh"
ui_init_logging

main() {
    local src="$SOURCE_DIR"
    local reset=0 reply arg
    local -a rest
    for arg in "$@"; do
        case "$arg" in
            -r | --reset) reset=1 ;;
            -h | --help)
                echo "usage: chez setup [--reset|-r]"
                echo "  (no flag)      fill in newly-added setup keys only; keeps existing answers"
                echo "  --reset, -r    replay first-time setup: reset run-once state, re-ask everything"
                return 0
                ;;
            *) rest+=("$arg") ;;
        esac
    done

    if [ "$reset" -eq 1 ]; then
        # Self-heal a stale wizard path before the destructive state reset below.
        (cd "$src" && git pull --ff-only) || return $?
        # `[ -r /dev/tty ]` is unreliable, so actually try to open it.
        if { : </dev/tty; } 2>/dev/null; then
            printf 'chez setup --reset: replay first-time setup (reset run-once state, re-ask the wizard)? [y/N] '
            IFS= read -r reply </dev/tty || reply=""
            case "$reply" in
                y | Y | yes | YES) ;;
                *)
                    echo "aborted — nothing changed"
                    return 0
                    ;;
            esac
        fi
        # Check the wizard exists BEFORE resetting run-once state. The reset is
        # the destructive half; failing after it and before the wizard would
        # leave the machine with every hook pending and no way to answer the
        # questions. The zsh version got this right via _chez_run's self-heal,
        # which ran ahead of the reset — this keeps the ordering explicit.
        if [ ! -x "$_DIR/cli.sh" ]; then
            printf 'chez setup: %s is missing — refusing to reset run-once state\n' "$_DIR/cli.sh" >&2
            printf '           re-sync the repo first: chez up\n' >&2
            return 1
        fi
        chezmoi state reset --force || return $?
        bash "$_DIR/cli.sh" ${rest[@]+"${rest[@]}"}
        return
    fi

    (cd "$src" && git pull --ff-only) || return $?
    echo "chez setup: filling in any new/unanswered setup keys only."
    echo "           to re-choose profile/modules/signing, run: chez setup --reset"
    chezmoi init && bash "$_DIR/../converge/apply.sh" ${rest[@]+"${rest[@]}"}
}

main "$@"
