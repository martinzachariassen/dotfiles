#!/usr/bin/env bash
# chezup.sh — converge this Mac to the repo: pull, preview drift, apply. No
# package version bumps (that's chezbump).
# Env: DRY_RUN=1 print instead of run; YES=1 skip the confirm gate; DOTFILES_DIR.

set -uo pipefail

SOURCE_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${YES:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=../lib/log.sh
if [ ! -r "$_DIR/../lib/log.sh" ]; then
    printf 'chezup: missing %s\n' "$_DIR/../lib/log.sh" >&2
    exit 1
fi
# shellcheck source=../lib/log.sh
. "$_DIR/../lib/log.sh"
ui_init_logging

run() {
    if [ "$DRY_RUN" = "1" ]; then
        dim "dry-run \$ $*"
        return 0
    fi
    "$@"
}

# ─── 1. Update repo ──────────────────────────────────────────────────────────
if [ ! -d "$SOURCE_DIR/.git" ]; then
    fail "no git repo at $SOURCE_DIR — run install.sh, or set DOTFILES_DIR"
    exit 1
fi
before="$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
if [ "$DRY_RUN" = "1" ]; then
    run git -C "$SOURCE_DIR" pull --ff-only
    after="$before"
elif ! git -C "$SOURCE_DIR" pull --ff-only >/dev/null 2>&1; then
    fail "git pull --ff-only failed — resolve it in $SOURCE_DIR, then re-run chezup"
    exit 1
else
    after="$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
fi
if [ "$before" = "$after" ]; then
    ok "repo up to date (${before:0:7})"
else
    pulled="$(git -C "$SOURCE_DIR" rev-list --count "$before..$after" 2>/dev/null || echo '?')"
    ok "pulled $pulled commit(s) (${before:0:7} → ${after:0:7})"
fi

# ─── 2. Review drift ─────────────────────────────────────────────────────────
if ! command -v chezmoi >/dev/null 2>&1; then
    fail "chezmoi is not on PATH — run install.sh, or brew install chezmoi"
    exit 1
fi
pending="$(chezmoi status --exclude scripts 2>/dev/null || true)"
if [ -z "$pending" ]; then
    ok "already in sync — no managed files drifted"
    exit 0
fi
count="$(printf '%s\n' "$pending" | grep -c .)"
info "$count managed file(s) drifted (A add · M modify · D remove):"
printf '%s\n' "$pending" | while IFS= read -r line; do
    [ -n "$line" ] && dim "    $line"
done

# ─── 3. Apply (single confirm gate) ──────────────────────────────────────────
if [ "$ASSUME_YES" != "1" ] && [ -r /dev/tty ]; then
    printf '%s  Apply these %s change(s)? [Y/n] ' "$(line_prefix)" "$count" >/dev/tty
    IFS= read -r reply </dev/tty || reply=""
    case "$reply" in
        n | N | no | NO)
            info "aborted — nothing changed"
            exit 0
            ;;
    esac
fi

info "chezmoi apply --force ${*:-}"
if [ "$DRY_RUN" = "1" ]; then
    run chezmoi apply --force "$@"
else
    chezmoi apply --force "$@" || {
        fail "apply failed"
        exit 1
    }
fi
ok "chezup complete"
