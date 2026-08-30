#!/usr/bin/env bash
# dry-run.sh — shared DRY_RUN wrapper for scripts that support previewing
# instead of running. Callers set DRY_RUN before sourcing this.
# shellcheck disable=SC2329

[ -n "${__DOTFILES_DRY_RUN_SH:-}" ] && return 0
__DOTFILES_DRY_RUN_SH=1

# run CMD... — executes CMD, or prints it (via log.sh's `dim`) and no-ops when
# DRY_RUN=1.
run() {
    if [ "$DRY_RUN" = "1" ]; then
        dim "dry-run \$ $*"
        return 0
    fi
    "$@"
}
