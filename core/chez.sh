#!/usr/bin/env bash
# chez.sh — the dispatcher behind `chez <verb>`.
#
# Every verb resolves through core/verbs.sh, so the command surface, the help
# text and the completion list are all one table. `chez cd` never reaches here:
# it has to change the calling shell's directory, so the zsh function handles it
# and this script only explains that if someone runs it by hand.

set -uo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${DOTFILES_DIR:-$(cd "$_DIR/.." && pwd)}"

# shellcheck source=verbs.sh
. "$_DIR/verbs.sh"

# ── module gating ────────────────────────────────────────────────────────────
# The zsh wrapper exports CHEZ_MODULES from render-time data: no subprocess, no
# jq, and exactly as accurate as the shell config it came from. Reading chezmoi
# is the fallback for a direct `bash core/chez.sh`, and costs ~200 ms — which is
# why the wrapper does not pay it.
#
# CHEZ_MODULES set-but-empty is a real answer (no modules enabled), so the
# fallback triggers on unset alone.
chez_modules() {
    if [ -n "${CHEZ_MODULES+set}" ]; then
        printf '%s\n' $CHEZ_MODULES # deliberately unquoted: split on spaces
        return 0
    fi
    command -v chezmoi >/dev/null 2>&1 || return 0
    # shellcheck source=chezmoi-data.sh
    . "$_DIR/chezmoi-data.sh"
    local json
    json="$(cm_data_json)"
    command -v jq >/dev/null 2>&1 || return 0
    printf '%s\n' "$json" | jq -r '(.modules // [])[]' 2>/dev/null
}

# chez_verb_active VERB — 0 when the verb exists on this Mac. A verb with no
# module gate is always active; a gated one needs its module enabled.
chez_verb_active() {
    local module
    module="$(verbs_module "$1")"
    case "$module" in "" | -) return 0 ;; esac
    chez_modules | grep -qx "$module"
}

# ── help ─────────────────────────────────────────────────────────────────────

# Group headings. Kept here rather than in the table because a heading is
# presentation, and the table is data every other caller reads.
chez_group_title() {
    case "$1" in
        everyday) printf 'Everyday\n' ;;
        setup) printf 'Change your setup\n' ;;
        maintenance) printf 'Maintenance (packages & drift)\n' ;;
        hood) printf 'Under the hood\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# chez_details VERB — the flag hints printed under a verb, if any. These are the
# verb's own CLI, not registry data: nothing outside `chez help` reads them, and
# folding multi-line text into a TSV table would cost more than it saves.
chez_details() {
    case "$1" in
        setup) printf '%s\n' '--reset/-r  set up as new: reset run-once state, re-ask everything.' ;;
        sign) printf '%s\n' 'Run this after 1Password is up if setup deferred the key.' ;;
        xcode) printf '%s\n' '--check  report the five readiness checks; changes nothing.' ;;
        distill)
            printf '%s\n' \
                '--setup   turn it on here: module, apply, nightly timer.' \
                '--status  where things live, MAIN size vs cap, spend, runs.' \
                '--render  rebuild from the corpus, no API calls.' \
                '--stats   the corpus: funnel, topics, spend, runs.' \
                '--runs [N]  a row per night  ·  --logs [N] [-f]  the log.' \
                '--since 7d  backfill         ·  --undo  revert + re-render.' \
                '--remote [URL|none]  back the corpus up, or stop.'
            ;;
        mirror)
            printf '%s\n' \
                '--all/-a      uninstall the whole set after one confirmation.' \
                '--dry-run/-n  preview only, remove nothing.'
            ;;
        clean) printf '%s\n' '--all/-a  remove the whole set after one confirmation.' ;;
        adopt)
            printf '%s\n' \
                '<package>  add it to the repo Brewfile — every Mac gets it.' \
                '--local    add it to this Mac only (~/.config/chez/Brewfile.local).' \
                '<path>     hand an existing dotfile to chezmoi.'
            ;;
    esac
}

chez_help() {
    local group verb detail
    printf '\n  ── dotfiles commands ─────────────────────────────────────────────\n'
    printf '  Converge this Mac to the repo. Two verbs day to day; the rest are\n'
    printf '  for setup changes and package drift.\n'
    while IFS= read -r group; do
        printf '\n  %s\n' "$(chez_group_title "$group")"
        while IFS= read -r verb; do
            chez_verb_active "$verb" || continue
            printf '    chez %-10s %s\n' "$verb" "$(verbs_summary "$verb")"
            while IFS= read -r detail; do
                printf '                    %s\n' "$detail"
            done < <(chez_details "$verb")
        done < <(verbs_in_group "$group")
    done < <(verbs_groups)
    cat <<'EOF'

  Add something new to the repo
    new brew pkg     add the line to features/brew/Brewfile* → chez apply
    new dotfile      chezmoi add ~/.foo   ·   update tracked: chezmoi re-add ~/.foo
    install.sh       Bootstrap a fresh Mac (curl | bash entry point).

  Knobs (chez up / apply / reconcile / clean):  DRY_RUN=1 print only  ·  YES=1 skip confirm
  QUIET=1 on any verb (and install.sh) drops the explanations, leaving just results
  chez mirror also honors DRY_RUN=1 / -n (preview only) and YES=1 (accept-all, no prompts)
  YES=1 chez clean:  accept-all — remove everything untracked, no prompts
  Every verb also answers to its old name for now: chez up == chez up.
  Deeper docs:  run `chez cd`, then see docs/commands.md
EOF
}

# chez_verbs — `verb:summary` per line, for the zsh completion. Only the verbs
# this Mac actually has, so completion and help can never disagree.
chez_verbs() {
    local verb
    while IFS= read -r verb; do
        chez_verb_active "$verb" || continue
        printf '%s:%s\n' "$verb" "$(verbs_summary "$verb")"
    done < <(verbs_all)
}

# ── dispatch ─────────────────────────────────────────────────────────────────

# chez_suggest VERB — the closest known verb, by shared prefix then substring.
# Cheap on purpose: an edit-distance implementation in bash would be more code
# than the dispatcher it helps.
chez_suggest() {
    local typo="$1" verb
    while IFS= read -r verb; do
        case "$verb" in "$typo"*) printf '%s\n' "$verb" ;; esac
    done < <(verbs_all)
    while IFS= read -r verb; do
        case "$typo" in "$verb"*) printf '%s\n' "$verb" ;; esac
    done < <(verbs_all)
}

main() {
    local verb="${1:-help}"
    case "$verb" in
        -h | --help) verb=help ;;
    esac
    shift 2>/dev/null || true

    case "$verb" in
        help)
            chez_help
            return 0
            ;;
        --verbs)
            chez_verbs
            return 0
            ;;
        cd)
            printf 'chez: `cd` has to run in your shell, not a subprocess.\n' >&2
            printf '      Use the shell function: chez cd\n' >&2
            return 1
            ;;
    esac

    local rel
    rel="$(verbs_path "$verb")"
    if [ -z "$rel" ] || [ "$rel" = "-" ]; then
        printf 'chez: unknown verb: %s\n' "$verb" >&2
        local near
        near="$(chez_suggest "$verb" | head -1)"
        [ -n "$near" ] && printf '      did you mean: chez %s\n' "$near" >&2
        printf '      run `chez help` for the full list\n' >&2
        return 2
    fi

    if ! chez_verb_active "$verb"; then
        local module
        module="$(verbs_module "$verb")"
        printf 'chez %s needs the `%s` module, which is not enabled here.\n' "$verb" "$module" >&2
        printf '      Turn it on with: chez setup\n' >&2
        return 1
    fi

    if [ ! -f "$ROOT/$rel" ]; then
        printf 'chez: %s is missing from %s\n' "$rel" "$ROOT" >&2
        printf '      re-sync the repo: chez up\n' >&2
        return 1
    fi

    exec bash "$ROOT/$rel" "$@"
}

main "$@"
