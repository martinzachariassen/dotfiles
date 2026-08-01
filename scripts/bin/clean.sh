#!/usr/bin/env bash
# clean.sh — mirror the TOP LEVEL of $HOME to what chezmoi manages: surface
# untracked ~/.* entries (minus a keep-list) and remove only what you confirm.
# The file analogue of chezmirror (which does the same for Homebrew packages).
#
# Scope is deliberately narrow and safe:
#   • only entries whose name begins with "." are ever considered, so ~/Library,
#     ~/Documents, ~/Developer and other user data are out of scope structurally;
#   • it NEVER descends into a directory — only whole top-level entries;
#   • ~/.config is governed separately (exact_ dir + keep-list in .chezmoiignore),
#     so it is always kept here;
#   • nothing is removed without a confirmation (or an explicit --all / YES=1),
#     and never at all without a controlling terminal.
#
# Keep-list is the single source of truth in src/.chezmoidata/cleanup.toml
# (.cleanup.keepHome), read through chezmoi's own template engine — so it can't
# drift from the ~/.config keep-list and needs no jq. Unlike a chezmoi hook this
# verb runs with a live stdin, so it talks to /dev/tty directly (no tty.sh).
#
# Env: DRY_RUN=1 preview without deleting (works headless); YES=1 accept-all.
#      CHEZCLEAN_TARGET overrides $HOME (tests only).

set -uo pipefail

TARGET="${CHEZCLEAN_TARGET:-$HOME}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${YES:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$_DIR/../lib/log.sh" ]; then
    printf 'chezclean: missing %s\n' "$_DIR/../lib/log.sh" >&2
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

# ─── pure helpers (unit-tested against stubbed inputs) ────────────────────────

# _clean_home_dotentries DIR — basenames of top-level entries in DIR beginning
# with "." (dirs, files, symlinks incl. dangling), excluding . and .., one per
# line, sorted. Never descends. Dangling symlinks count (they're cruft too).
_clean_home_dotentries() {
    local dir="$1" path name
    [ -d "$dir" ] || return 0
    for path in "$dir"/.*; do
        name="${path##*/}"
        case "$name" in
            . | ..) continue ;;
        esac
        # A glob that matches nothing yields the literal pattern; guard against it.
        [ -e "$path" ] || [ -L "$path" ] || continue
        printf '%s\n' "$name"
    done | sort
}

# _clean_managed_top — top-level chezmoi-managed target components beginning with
# "." (e.g. .config, .zshenv, .ssh), one per line, sorted-unique. `chezmoi
# managed` lists target-relative paths; we keep only the first path segment.
_clean_managed_top() {
    chezmoi managed 2>/dev/null |
        sed 's#/.*##' |
        grep '^\.' |
        sort -u
}

# _clean_keep_home — the keep-list from the single source of truth, via chezmoi's
# template engine (no jq; can't drift from the .chezmoiignore keep-list).
_clean_keep_home() {
    chezmoi execute-template '{{ range .cleanup.keepHome }}{{ . }}{{ "\n" }}{{ end }}' 2>/dev/null
}

# _clean_candidates MANAGED KEEP — read home dot-entries on stdin; emit those
# that chezmoi neither manages (MANAGED, newline list) nor the keep-list spares
# (KEEP, newline list). Pure: no filesystem, no chezmoi — fully stubbable.
_clean_candidates() {
    local managed="$1" keep="$2" entry
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        printf '%s\n' "$managed" | grep -qxF -- "$entry" && continue
        printf '%s\n' "$keep" | grep -qxF -- "$entry" && continue
        printf '%s\n' "$entry"
    done
}

# _clean_kind PATH — one-word type label for the preview.
_clean_kind() {
    if [ -L "$1" ]; then
        printf 'symlink'
    elif [ -d "$1" ]; then
        printf 'dir'
    elif [ -f "$1" ]; then
        printf 'file'
    else
        printf 'other'
    fi
}

# _clean_remove_one PATH — remove a top-level entry. rm -f for a symlink (never
# follow it), rm -rf otherwise. Routed through run() so DRY_RUN only prints.
_clean_remove_one() {
    if [ -L "$1" ]; then
        run rm -f "$1"
    else
        run rm -rf "$1"
    fi
}

_clean_help() {
    cat <<'EOF'
usage: chezclean [--all|-a | --yes|-y] [--dry-run|-n]

  Mirror the top level of $HOME to what chezmoi manages: list untracked ~/.*
  entries (minus the keep-list) and remove only what you confirm.

  (no flag)     confirm each candidate individually
  --all, -a     remove the whole set after ONE confirmation (alias: --yes, -y)
  --dry-run, -n preview what would be removed; delete nothing (also DRY_RUN=1)

  YES=1 chezclean   accept-all with no prompt (still needs a terminal).
  Keep an entry for good: add it to keepHome in src/.chezmoidata/cleanup.toml.
EOF
}

# ─── main ─────────────────────────────────────────────────────────────────────
_clean_main() {
    local all=0 bulk_confirm=1 arg
    [ "$ASSUME_YES" = "1" ] && {
        all=1
        bulk_confirm=0
    }
    for arg in "$@"; do
        case "$arg" in
            -a | --all | -y | --yes) all=1 ;;
            -n | --dry-run) DRY_RUN=1 ;;
            -h | --help)
                _clean_help
                return 0
                ;;
            *)
                fail "unknown option: $arg (try --help)"
                return 2
                ;;
        esac
    done
    # A dry-run deletes nothing, so preview the whole set unconditionally and
    # skip the terminal requirement — it's a safe read-only report anywhere.
    if [ "$DRY_RUN" = "1" ]; then
        all=1
        bulk_confirm=0
    fi

    if ! command -v chezmoi >/dev/null 2>&1; then
        fail "chezmoi is not on PATH — run install.sh, or brew install chezmoi"
        return 1
    fi

    local keep managed entries candidates count
    keep="$(_clean_keep_home)"
    if [ -z "$keep" ]; then
        fail "empty keep-list (could not read .cleanup.keepHome) — refusing to touch \$HOME"
        return 1
    fi
    managed="$(_clean_managed_top)"
    entries="$(_clean_home_dotentries "$TARGET")"
    candidates="$(printf '%s\n' "$entries" | _clean_candidates "$managed" "$keep")"

    if [ -z "$candidates" ]; then
        ok "\$HOME top level is clean — every ~/.* entry is managed or kept"
        return 0
    fi

    count="$(printf '%s\n' "$candidates" | grep -c .)"
    info "$count untracked top-level entr$([ "$count" -eq 1 ] && printf y || printf ies) — not managed by chezmoi, not on the keep-list:"
    local c
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        dim "    $c ($(_clean_kind "$TARGET/$c"))"
    done <<<"$candidates"
    hr

    # No controlling terminal ⇒ remove nothing. DRY_RUN is exempt: it deletes
    # nothing, so it stays a safe preview that works headless (e.g. in CI).
    if [ "$DRY_RUN" != "1" ] && ! { : </dev/tty; } 2>/dev/null; then
        warn "no TTY — not removing. Re-run interactively, or use --all / YES=1."
        return 0
    fi

    # One bulk confirm for --all (YES=1 already cleared bulk_confirm).
    if [ "$all" -eq 1 ] && [ "$bulk_confirm" -eq 1 ]; then
        local ok_batch
        if command -v gum >/dev/null 2>&1; then
            gum confirm "Remove ALL $count untracked entr$([ "$count" -eq 1 ] && printf y || printf ies)?" && ok_batch=1 || ok_batch=0
        else
            local reply
            printf '%s  Remove ALL %s untracked entr%s? [y/N] ' "$(line_prefix)" "$count" "$([ "$count" -eq 1 ] && printf y || printf ies)" >/dev/tty
            IFS= read -r reply </dev/tty || reply=""
            case "$reply" in y | Y | yes | YES) ok_batch=1 ;; *) ok_batch=0 ;; esac
        fi
        [ "$ok_batch" -eq 1 ] || {
            info "aborted — nothing removed"
            return 0
        }
    fi

    # Phase 1 — decide. Confirm each entry (unless accept-all); collect approvals.
    # Feed the list on fd 3, keeping stdin on the terminal so gum reads keypresses.
    local approved="" kept=0 name reply ok_one
    while IFS= read -r name <&3; do
        [ -n "$name" ] || continue
        if [ "$all" -eq 1 ]; then
            ok_one=1
        elif command -v gum >/dev/null 2>&1; then
            gum confirm "Remove $name ($(_clean_kind "$TARGET/$name"))?" && ok_one=1 || ok_one=0
        else
            printf '%s  Remove %s (%s)? [y/N] ' "$(line_prefix)" "$name" "$(_clean_kind "$TARGET/$name")" >/dev/tty
            IFS= read -r reply </dev/tty || reply=""
            case "$reply" in y | Y | yes | YES) ok_one=1 ;; *) ok_one=0 ;; esac
        fi
        if [ "$ok_one" -eq 1 ]; then
            approved+="$name"$'\n'
        else
            kept=$((kept + 1))
        fi
    done 3<<<"$candidates"

    # Phase 2 — remove the approved set.
    local removed=0
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        if _clean_remove_one "$TARGET/$name"; then
            removed=$((removed + 1))
        else
            warn "could not remove $name — remove it by hand"
        fi
    done <<<"$approved"

    hr
    ok "removed $removed · kept $kept"
    return 0
}

# Run unless sourced (tests source the file to exercise the pure helpers).
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
    _clean_main "$@"
fi
