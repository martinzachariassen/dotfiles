#!/usr/bin/env bash
# distill.sh — chezdistill: distil Claude Code conversations into the Obsidian
# vault, and render the MAIN.md that every future session loads.
# Env: DRY_RUN=1 print instead of run; YES=1 skip confirm gates; DOTFILES_DIR;
#      DISTILL_SINCE=ISO override the cursor.

set -uo pipefail

DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${YES:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$_DIR/../lib/log.sh" ]; then
    printf 'chezdistill: missing %s\n' "$_DIR/../lib/log.sh" >&2
    exit 1
fi
# shellcheck source=../lib/log.sh
. "$_DIR/../lib/log.sh"
ui_init_logging
ui_init_status
# shellcheck source=../lib/dry-run.sh
. "$_DIR/../lib/dry-run.sh"
# shellcheck source=../lib/distill.sh
. "$_DIR/../lib/distill.sh"

_distill_help() {
    cat <<'EOF'
usage: chezdistill [--weekly] [--since SPEC] [--status] [--render] [--undo] [-n]

Distil recent Claude Code conversations into ~/Documents/TheArchive/30-Claude:
a daily report, a weekly review, and a size-capped MAIN.md that is loaded into
every future session.

  (no flags)        run the nightly job now — the same code path launchd uses
  --weekly          run the weekly review and compaction now
  --since SPEC      backfill from a point in time: 7d, 24h, or an ISO timestamp
  --status          preflight, MAIN size vs cap, unclassified origins, spend
  --render          rebuild MAIN.md, Inbox and Topics from the ledger; no API calls
  --undo            revert the vault's most recent chezdistill commit
  -n, --dry-run     show what would be read and run, without calling the model
  -h, --help        this text

The vault is never created by this command. If it is missing, the job exits
without doing anything — clone or mount it first.
EOF
}

# _distill_since SPEC — 7d / 24h / ISO-8601 → an ISO-8601 Z timestamp.
_distill_since() {
    case "$1" in
        *[0-9]d)
            distill_iso_ago "${1%d}"
            ;;
        *[0-9]h)
            date -u -v-"${1%h}"H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
                date -u -d "${1%h} hours ago" +%Y-%m-%dT%H:%M:%SZ
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

_distill_undo() {
    local last
    distill_preflight || return $?
    last="$(git -C "$DISTILL_VAULT" log --format='%H %s' -20 |
        grep -m1 'chore(distill)' | cut -d' ' -f1)"
    if [ -z "$last" ]; then
        info "no chezdistill commit found in the vault's last 20 commits"
        return 0
    fi
    say "would revert $(git -C "$DISTILL_VAULT" log -1 --format='%h %s' "$last")"
    if [ "$ASSUME_YES" != "1" ] && [ "$DRY_RUN" != "1" ] && { : </dev/tty; } 2>/dev/null; then
        printf '%s  %s' "$(line_prefix)" "Revert it? [y/N] " >/dev/tty
        IFS= read -r reply </dev/tty || reply=""
        case "$reply" in
            y | Y | yes | YES) ;;
            *)
                info "aborted — nothing changed"
                return 0
                ;;
        esac
    fi
    run git -C "$DISTILL_VAULT" revert --no-edit "$last"
}

_distill_main() {
    local mode=run

    while [ $# -gt 0 ]; do
        case "$1" in
            --weekly) mode=weekly ;;
            --status) mode=status ;;
            --render) mode=render ;;
            --undo) mode=undo ;;
            --since=*) DISTILL_SINCE="$(_distill_since "${1#--since=}")" ;;
            --since)
                [ $# -ge 2 ] || {
                    fail "--since needs a value (7d, 24h, or an ISO timestamp)"
                    return 2
                }
                shift
                DISTILL_SINCE="$(_distill_since "$1")"
                ;;
            -n | --dry-run) DRY_RUN=1 ;;
            -y | --yes) ASSUME_YES=1 ;;
            -h | --help)
                _distill_help
                return 0
                ;;
            *)
                fail "unknown option: $1 (try --help)"
                return 2
                ;;
        esac
        shift
    done
    export DISTILL_SINCE DRY_RUN

    if [ "$mode" = "status" ]; then
        distill_status
        return 0
    fi
    if [ "$mode" = "undo" ]; then
        _distill_undo
        return $?
    fi

    echo
    printf '%s%s%s  %sDistilling Claude Code conversations%s\n' \
        "$CYAN" "$NODE" "$RESET" "$BOLD" "$RESET"
    explain \
        "Read what you and Claude worked out since the last run, and write it up." \
        "Only entries seen in two separate sessions reach MAIN.md."

    distill_preflight
    case "$?" in
        0) ;;
        2)
            info "nothing to do"
            return 0
            ;;
        *) return 1 ;;
    esac

    case "$mode" in
        render)
            distill_render_main
            distill_render_inbox
            distill_render_topics
            ok "rendered MAIN.md, Inbox and Topics from the ledger"
            ;;
        weekly)
            distill_run_weekly || return 1
            ok "weekly review written"
            ;;
        run)
            distill_run_daily || return 1
            ok "daily report written"
            ;;
    esac
    return 0
}

# Tests source this file to exercise the pure helpers, so only run when executed.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
    _distill_main "$@"
fi
