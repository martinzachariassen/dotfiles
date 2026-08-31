#!/usr/bin/env bash
# up.sh — converge this Mac to the repo: pull, offer any module the catalog
# gained since setup, preview drift, apply. No package version bumps (that's
# chez bump).
# Env: DRY_RUN=1 print instead of run; YES=1 skip the confirm gate; DOTFILES_DIR.

set -uo pipefail

SOURCE_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${YES:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=../../core/ui.sh
if [ ! -r "$_DIR/../../core/ui.sh" ]; then
    printf 'chez up: missing %s\n' "$_DIR/../../core/ui.sh" >&2
    exit 1
fi
# shellcheck source=../../core/ui.sh
. "$_DIR/../../core/ui.sh"
ui_init_logging
# shellcheck source=../../core/dry-run.sh
. "$_DIR/../../core/dry-run.sh"
# shellcheck source=../../core/modules.sh
. "$_DIR/../../core/modules.sh"

# offer_new_modules — offer every catalog module this Mac has never been asked
# about, exactly once.
#
# promptMultichoiceOnce keeps the first answer forever and chez up only ever runs
# `apply`, so without this a module added to the catalog after a machine was set
# up is reachable only through `chez setup --reset`, which re-asks everything.
# Runs after the pull (the catalog may have just grown) and before the drift
# check, so a module enabled here is applied in the same run.
#
# Every module offered is recorded in `modulesSeen` whether or not it was
# accepted — that is what stops a declined module being asked about every run.
offer_new_modules() {
    local json cfg fresh enabled seen accepted="" m label reply count=0

    command -v jq >/dev/null 2>&1 || return 0
    json="$(chezmoi data --format=json 2>/dev/null)"
    [ -n "$json" ] || return 0

    fresh="$(modules_unseen "$json" | tr '\n' ' ' | sed 's/ *$//')"
    [ -n "${fresh// /}" ] || return 0
    for m in $fresh; do count=$((count + 1)); done

    if [ "$count" -eq 1 ]; then
        info "1 new module since this Mac was set up:"
    else
        info "$count new modules since this Mac was set up:"
    fi
    for m in $fresh; do
        label="$(modules_label "$json" "$m")"
        dim "    $m — ${label:-no description}"
    done

    if [ "$DRY_RUN" = "1" ]; then
        explain "dry-run — not asking, and not touching the module list."
        return 0
    fi

    # Enabling a module rewrites this Mac's configuration rather than just
    # installing what it already asked for, so it is never done unattended:
    # YES=1 means "don't ask before applying", not "decide for me".
    if [ "$ASSUME_YES" = "1" ] || [ ! -r /dev/tty ]; then
        explain "Not enabling anything unattended — run chez up from a terminal to choose."
        return 0
    fi

    cfg="$(modules_config_file)"
    if [ ! -w "$cfg" ]; then
        warn "$cfg is not writable — cannot record an answer"
        explain "Choose modules by hand instead: chez setup --reset"
        return 0
    fi

    for m in $fresh; do
        printf '%s  Enable %s? [y/N] ' "$(line_prefix)" "$m" >/dev/tty
        IFS= read -r reply </dev/tty || reply=""
        case "$reply" in
            y | Y | yes | YES) accepted="${accepted:+$accepted }$m" ;;
        esac
    done

    enabled="$(modules_enabled "$json" | tr '\n' ' ')${accepted:+ $accepted}"
    seen="$(modules_seen "$json" | tr '\n' ' ')$fresh"

    # modulesSeen first: if the second write fails, the worst case is being
    # asked again — the reverse would silently enable a module and forget it.
    if ! modules_write_list "$cfg" modulesSeen $seen; then
        warn "could not record the answer in $cfg — you will be asked again"
        return 0
    fi
    [ -n "$accepted" ] || {
        ok "left off: $fresh"
        return 0
    }
    if modules_write_list "$cfg" modules $enabled; then
        ok "enabled: $accepted"
    else
        fail "could not write the module list to $cfg"
    fi
    return 0
}

echo
printf '%s%s%s  %sConverging this Mac to the repo%s\n' "$CYAN" "$NODE" "$RESET" "$BOLD" "$RESET"
explain \
    "Pull the latest config, show what would change, then apply it." \
    "Installs what's missing; it never uninstalls or downgrades anything."

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
    fail "git pull --ff-only failed — resolve it in $SOURCE_DIR, then re-run chez up"
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

# ─── 2. Offer modules this Mac has never been asked about ────────────────────
if ! command -v chezmoi >/dev/null 2>&1; then
    fail "chezmoi is not on PATH — run install.sh, or brew install chezmoi"
    exit 1
fi
offer_new_modules

# ─── 3. Review drift ─────────────────────────────────────────────────────────
# Two questions, not one: managed files can be perfectly in sync while apply
# hooks (brew bundle, mise, VS Code, macOS defaults) still have work to do —
# a partial install leaves no file drift at all. Gating only on file drift is
# what used to make chez up a no-op exactly when a retry was needed.
pending="$(chezmoi status --exclude scripts 2>/dev/null || true)"
hooks="$(chezmoi status --include scripts 2>/dev/null || true)"
count=0
[ -n "$pending" ] && count="$(printf '%s\n' "$pending" | grep -c .)"
hook_count=0
[ -n "$hooks" ] && hook_count="$(printf '%s\n' "$hooks" | grep -c .)"

if [ "$count" -eq 0 ] && [ "$hook_count" -eq 0 ]; then
    ok "already in sync — no managed files drifted, no hooks pending"
    exit 0
fi
if [ "$count" -gt 0 ]; then
    info "$count managed file(s) drifted (A add · M modify · D remove):"
    printf '%s\n' "$pending" | while IFS= read -r line; do
        [ -n "$line" ] && dim "    $line"
    done
else
    ok "no managed files drifted"
fi
if [ "$hook_count" -gt 0 ]; then
    info "$hook_count apply hook(s) pending (packages, runtimes, extensions, defaults)"
    explain "Hooks are idempotent — a re-run installs only what is still missing."
fi

# ─── 4. Apply (single confirm gate) ──────────────────────────────────────────
if [ "$ASSUME_YES" != "1" ] && [ -r /dev/tty ]; then
    if [ "$count" -gt 0 ]; then
        gate="Apply these $count change(s)? [Y/n] "
    else
        gate="Run the $hook_count pending hook(s)? [Y/n] "
    fi
    printf '%s  %s' "$(line_prefix)" "$gate" >/dev/tty
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
ok "chez up complete"
