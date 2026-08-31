#!/usr/bin/env bash
# chez mirror — uninstall Homebrew packages no active Brewfile tier declares.
#
# Removal only. A routine apply must never silently uninstall, so this is a verb
# you run deliberately; chez reconcile chains chez up (install) then this (remove),
# and chez status is the read-only preview of the same set.
#
# Was ~155 lines of zsh inside dot_zshrc.tmpl, where no linter could see it.

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

    local all=0 bulk_confirm=1 dry=0 arg
    [ "${YES:-}" = 1 ] && {
        all=1
        bulk_confirm=0
    }
    [ "${DRY_RUN:-}" = 1 ] && dry=1
    for arg in "$@"; do
        case "$arg" in
            -a | --all | -y | --yes) all=1 ;;
            -n | --dry-run) dry=1 ;;
            -h | --help)
                echo "usage: chez mirror [--all|-a | --yes|-y] [--dry-run|-n]"
                echo "  removal only — installs happen via chez up / chez apply; chez reconcile does both."
                echo "  (no flag)      confirm each untracked package individually"
                echo "  --all, -a      uninstall the whole untracked set after ONE confirmation"
                echo "  --yes, -y      alias of --all;  YES=1 chez mirror skips that confirmation"
                echo "  --dry-run, -n  preview the untracked set only, remove nothing;  DRY_RUN=1 chez mirror does the same"
                return 0
                ;;
            *)
                echo "chez mirror: unknown option: $arg (try --help)" >&2
                return 2
                ;;
        esac
    done

    explain_titled "Untracked packages" \
        "Finds Homebrew packages installed on this Mac that no active Brewfile" \
        "declares — the core file, your modules' tiers and Brewfile.local — then" \
        "offers to uninstall them. This is the only verb that removes packages;" \
        "apply and chez up never do. Each removal is confirmed separately."

    # Distinguish "resolved, and nothing is untracked" from "could not resolve"
    # — both yield an empty set, but only the first is a clean bill of health.
    local parsed rc
    parsed=$(brew_removals "$src")
    rc=$?

    if [ "$rc" -ne 0 ]; then
        echo "  ! could not determine what this machine tracks — nothing removed"
        echo "    fix the error above (usually: run \`chez up\`), then re-run chez mirror"
        return 1
    fi
    if [ -z "$parsed" ]; then
        echo "  ✓ nothing to remove — every installed package is tracked"
        return 0
    fi

    echo "── Untracked (installed locally, in no active Brewfile tier) ──"
    printf '%s\n' "$parsed" | awk -F'\t' '{ printf "  %-8s %s\n", $1, $2 }'
    echo

    if [ "$dry" -eq 1 ]; then
        echo "  DRY_RUN — nothing removed. Re-run without --dry-run to uninstall."
        return 0
    fi

    # `[ -r /dev/tty ]` is unreliable, so actually try to open it.
    if ! { : </dev/tty; } 2>/dev/null; then
        echo "No TTY — not removing. Re-run interactively to confirm each."
        return 0
    fi

    if [ "$all" -eq 1 ] && [ "$bulk_confirm" -eq 1 ]; then
        local count ok
        count=$(printf '%s\n' "$parsed" | grep -c .)
        if command -v gum >/dev/null 2>&1; then
            gum confirm "Uninstall ALL $count untracked package(s)?" && ok=1 || ok=0
        else
            local reply
            printf 'Uninstall ALL %s untracked package(s)? [y/N] ' "$count"
            IFS= read -r reply </dev/tty || reply=""
            case "$reply" in y | Y | yes | YES) ok=1 ;; *) ok=0 ;; esac
        fi
        [ "$ok" -eq 1 ] || {
            echo "aborted — nothing removed"
            return 0
        }
    fi

    # Phase 1 — decide, without uninstalling yet. List on fd 3, not stdin: `gum
    # confirm` reads keypresses from stdin, so a here-string there would drain it.
    local kind name reply ok kept=0 approved=""
    while IFS=$'\t' read -r kind name <&3; do
        [ -n "$name" ] || continue
        if [ "$all" -eq 1 ]; then
            ok=1
        elif command -v gum >/dev/null 2>&1; then
            gum confirm "Uninstall ${kind} ${name}?" && ok=1 || ok=0
        else
            printf 'Uninstall %s %s? [y/N] ' "$kind" "$name"
            IFS= read -r reply </dev/tty || reply=""
            case "$reply" in y | Y | yes | YES) ok=1 ;; *) ok=0 ;; esac
        fi
        if [ "$ok" -eq 1 ]; then
            approved+="${kind}"$'\t'"${name}"$'\n'
        else
            kept=$((kept + 1))
        fi
    done 3<<<"$parsed"

    # Phase 2 — remove, retrying in passes: `brew bundle cleanup` lists deps
    # before dependents, so shared deps fail until the leaves above them are
    # gone. Loop until a pass removes nothing. List on fd 3 again to keep
    # brew's stdin on the terminal.
    local removed=0 pending=$approved progressed leftover
    while [ -n "$pending" ]; do
        progressed=0 leftover=""
        while IFS=$'\t' read -r kind name <&3; do
            [ -n "$name" ] || continue
            if brew_uninstall_one "$kind" "$name" 2>/dev/null; then
                removed=$((removed + 1))
                progressed=1
            else
                leftover+="${kind}"$'\t'"${name}"$'\n'
            fi
        done 3<<<"$pending"
        pending=$leftover
        [ "$progressed" -eq 1 ] || break
    done

    if [ -n "$pending" ]; then
        echo
        echo "  ! still installed — a package outside your Brewfiles still needs these:"
        printf '%s' "$pending" | awk -F'\t' 'NF { printf "      %-8s %s\n", $1, $2 }'
    fi

    echo
    echo "  removed $removed · kept $kept"

    # `brew autoremove` only touches orphaned dependency-only formulae, never a
    # Brewfile-tracked package, so it's safe to offer after a removal pass.
    local orphans ocount oyes oreply
    orphans="$(brew autoremove -n 2>/dev/null | grep -vE '^==>' | grep -E '^[^[:space:]]+$' || true)"
    if [ -n "$orphans" ]; then
        ocount=$(printf '%s\n' "$orphans" | grep -c .)
        echo
        echo "── Orphaned dependencies (needed by nothing in your Brewfiles) ────"
        printf '%s\n' "$orphans" | awk 'NF { printf "  %s\n", $0 }'
        echo
        if [ "$all" -eq 1 ]; then
            oyes=1
        elif command -v gum >/dev/null 2>&1; then
            gum confirm "Prune $ocount orphaned dependency(ies) with brew autoremove?" && oyes=1 || oyes=0
        else
            printf 'Prune %s orphaned dependency(ies) with brew autoremove? [y/N] ' "$ocount"
            IFS= read -r oreply </dev/tty || oreply=""
            case "$oreply" in y | Y | yes | YES) oyes=1 ;; *) oyes=0 ;; esac
        fi
        if [ "$oyes" -eq 1 ]; then
            brew autoremove
            echo "  ✓ pruned orphaned dependencies"
        else
            echo "  kept orphaned dependencies — run \`brew autoremove\` to prune later."
        fi
    fi
    return 0
}

main "$@"
