#!/usr/bin/env bash
# distill.sh — chezdistill: distil Claude Code conversations into the memory tier
# every future session loads.
# Env: DRY_RUN=1 print instead of run; YES=1 skip confirm gates; DOTFILES_DIR;
#      DISTILL_SINCE=ISO override the cursor.

set -uo pipefail

DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${YES:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$_DIR/../../core/ui.sh" ]; then
    printf 'chezdistill: missing %s\n' "$_DIR/../../core/ui.sh" >&2
    exit 1
fi
# shellcheck source=../../core/ui.sh
. "$_DIR/../../core/ui.sh"
ui_init_logging
ui_init_status
# shellcheck source=../../core/dry-run.sh
. "$_DIR/../../core/dry-run.sh"
# shellcheck source=lib.sh
. "$_DIR/lib.sh"
# shellcheck source=../../core/chezmoi-data.sh
. "$_DIR/../../core/chezmoi-data.sh"
# shellcheck source=../../core/modules.sh
. "$_DIR/../../core/modules.sh"

_distill_help() {
    cat <<'EOF'
usage: chezdistill [--setup] [--since SPEC] [--status] [--stats] [--runs [N]]
                   [--logs [N] [-f]] [--render] [--remote [URL|none]] [--undo] [-n]

Distil recent Claude Code conversations into two places:

  ~/.config/claude/memory     MAIN.md, Topics/, Candidates.md — read by Claude
  ~/.local/state/chezdistill  the extract corpus, Pinned.md, cursor, spend, runs

  (no flags)        run the nightly job now — the same code path launchd uses
  --setup           turn it on for this Mac: enable the module, apply, register
                    the timer. Idempotent, no API calls
  --since SPEC      backfill from a point in time: 7d, 24h, or an ISO timestamp
  --render          rebuild MAIN.md, Topics and Candidates from the corpus;
                    no API calls
  --remote URL      back this Mac's corpus up to URL. Restores an existing corpus
                    onto a new Mac, and joins one that two Macs share
  --remote none     stop pushing — everything stays here, nothing is deleted
  --undo            revert the state repo's last chezdistill commit and
                    re-render the memory tier from it
  -n, --dry-run     show what would be read and run, without calling the model
  -h, --help        this text

Looking at it, rather than running it — all read-only, none cost anything:

  --status          paths, transcript sources, MAIN size vs cap, spend, last run
  --stats           the corpus: how many rules, what reached MAIN, what is still
                    waiting on a second sighting, by topic and kind, spend
  --runs [N]        the last N runs as a table (default 14) — the view that shows
                    a job that has been reporting ok and doing nothing
  --logs [N] [-f]   tail the nightly launchd log (default 50 lines); -f follows
  --remote          where this corpus backs up, or that it is local only

Before the module is enabled the `chez distill` shell verb does not exist yet, so
the very first run goes through the script:
  bash ~/Developer/personal/dotfiles/features/distill/cli.sh --setup
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

# _distill_undo — revert the extract corpus, then rebuild the memory tier from it. MAIN.md, Topics/ and Candidates.md are derived, so undoing the
# inputs and re-rendering is what actually puts them back; reverting the rendered
# files would leave them free to disagree with the corpus that produced them.
_distill_undo() {
    local last repo
    distill_preflight || return $?
    repo="$(distill_state_dir)"

    if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        info "no state repo at $repo yet — nothing to undo"
        return 0
    fi
    last="$(git -C "$repo" log --format='%H %s' -20 |
        grep -m1 'chore(distill)' | cut -d' ' -f1)"
    if [ -z "$last" ]; then
        info "no chezdistill commit in the state repo's last 20 commits"
        return 0
    fi
    say "would revert $(git -C "$repo" log -1 --format='%h %s' "$last")"
    explain "Then re-render MAIN.md, Topics and Candidates from the reverted corpus."
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
    run git -C "$repo" revert --no-edit "$last" || return 1
    [ "$DRY_RUN" = "1" ] && return 0
    distill_render_all
    ok "reverted, and re-rendered the memory tier from the corpus"
}

# ─── Setup ────────────────────────────────────────────────────────────────────
#
# `--setup` turns the feature on for this Mac and nothing more: the module list,
# an apply, the launchd timer. The memory dir and the state dir are ordinary local
# directories with no mount to be wrong about, so they are simply created.

# _distill_confirm PROMPT — 0 to proceed. Nothing here is destructive, so a
# missing terminal declines rather than aborting the whole run.
_distill_confirm() {
    [ "$DRY_RUN" = "1" ] && return 0
    [ "$ASSUME_YES" = "1" ] && return 0
    { : </dev/tty; } 2>/dev/null || return 1
    printf '%s  %s [Y/n] ' "$(line_prefix)" "$1" >/dev/tty
    IFS= read -r reply </dev/tty || return 1
    case "$reply" in
        n | N | no | NO) return 1 ;;
        *) return 0 ;;
    esac
}

# _distill_setup_module — put claudeDistiller into the chezmoi module list.
# Edits the single `modules = [...]` line rather than re-running `chezmoi init`:
# init re-derives every other saved answer, and this has to change exactly one.
# The edit itself lives in core/modules.sh, shared with chez up's
# new-module gate so the two cannot write the list differently.
# 0 = already on · 3 = turned on now (an apply is needed) · 1 = could not.
_distill_setup_module() {
    local cfg json enabled seen
    if ! command -v chezmoi >/dev/null 2>&1; then
        s_warn "module   chezmoi is not on PATH — skipping the module check"
        return 1
    fi
    json="$(cm_data_json)"
    if cm_has_module "$json" claudeDistiller; then
        s_pass "module   claudeDistiller is enabled"
        return 0
    fi

    cfg="$(modules_config_file)"
    if [ ! -w "$cfg" ]; then
        s_fail "module   claudeDistiller is off, and $cfg is not writable"
        explain "Turn it on by hand instead: chez setup, and tick claudeDistiller."
        return 1
    fi
    if ! grep -q '^[[:space:]]*modules[[:space:]]*=' "$cfg"; then
        s_fail "module   no 'modules =' line in $cfg"
        explain "Turn it on by hand instead: chez setup, and tick claudeDistiller."
        return 1
    fi

    enabled="$(modules_enabled "$json" | tr '\n' ' ')claudeDistiller"
    seen="$(modules_seen "$json" | tr '\n' ' ')claudeDistiller"

    s_note "module   claudeDistiller is off in $cfg"
    dim "           $(modules_toml_array $(modules_enabled "$json"))"
    dim "        →  $(modules_toml_array $enabled)"
    if ! _distill_confirm "Add claudeDistiller to the module list?"; then
        s_warn "module   left off — nothing else here will take effect"
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        dim "dry-run \$ edit $cfg"
        s_pass "module   claudeDistiller enabled"
        return 3
    fi
    if ! modules_write_list "$cfg" modules $enabled; then
        s_fail "module   could not rewrite $cfg"
        return 1
    fi
    # Record it as offered too, so chez up's gate stays quiet about a module
    # that has just been answered here.
    modules_write_list "$cfg" modulesSeen $seen || true
    s_pass "module   claudeDistiller enabled"
    return 3
}

# _distill_setup_agents — the launchd half. The plist is rendered by an apply,
# and hook 06 registers it; 3 means "it is not on disk yet, apply first".
# 0 = registered · 3 = the plist is missing · 1 = registration failed.
_distill_setup_agents() {
    local uid plist
    [ "$(uname -s)" = "Darwin" ] || {
        s_note "agents   not macOS — no launchd agent to register"
        return 0
    }
    command -v launchctl >/dev/null 2>&1 || {
        s_warn "agents   launchctl not on PATH"
        return 1
    }
    uid="$(id -u)"
    plist="$HOME/Library/LaunchAgents/no.mlz.chezdistill.nightly.plist"
    if [ ! -f "$plist" ]; then
        s_warn "agents   nightly plist not rendered yet"
        return 3
    fi
    if launchctl print "gui/$uid/no.mlz.chezdistill.nightly" >/dev/null 2>&1; then
        s_pass "agents   nightly registered"
        return 0
    fi
    if run launchctl bootstrap "gui/$uid" "$plist" 2>/dev/null; then
        s_pass "agents   nightly registered"
        return 0
    fi
    s_warn "agents   could not register nightly"
    return 1
}

_distill_setup() {
    local module_rc agents_rc needs_apply=0

    echo
    printf '%s%s%s  %sSetting up chezdistill on this Mac%s\n' \
        "$CYAN" "$NODE" "$RESET" "$BOLD" "$RESET"
    explain \
        "Turns on the module, applies, and registers the nightly timer." \
        "It makes no API calls."

    s_section "chezdistill setup"

    _distill_setup_module
    module_rc=$?
    [ "$module_rc" -eq 3 ] && needs_apply=1

    # An apply is also what puts the plist on disk, so a machine whose module
    # was already on but never applied gets offered the same fix.
    _distill_setup_agents
    agents_rc=$?
    [ "$agents_rc" -eq 3 ] && needs_apply=1

    if [ "$needs_apply" -eq 1 ]; then
        s_note "apply    needed — the plist and the MAIN.md import render there"
        if _distill_confirm "Run chezmoi apply now?"; then
            run chezmoi apply --force || s_warn "apply    chezmoi apply reported an error"
            _distill_setup_agents || true
        else
            s_warn "apply    skipped — run chez up before the timer can fire"
        fi
    fi

    # DISTILL_MEMORY and DISTILL_STATE are exported by preflight, and only by
    # preflight — everything below reads them.
    if ! distill_preflight >/dev/null 2>&1 && [ "$DRY_RUN" != "1" ]; then
        echo
        fail "setup incomplete — preflight refuses these paths"
        distill_status
        return 1
    fi

    # Seed MAIN.md from the (usually empty) corpus. The apply above rewrote the
    # global persona to @-import it, and an import that resolves to nothing is a
    # rough edge in every session until the first nightly run. Costs no API call.
    if [ "$DRY_RUN" = "1" ]; then
        s_note "render   skipped — a dry run has nothing to render from"
    elif [ -f "$(distill_memory_dir)/MAIN.md" ]; then
        s_pass "render   MAIN.md is present"
    else
        distill_render_all
        s_pass "render   seeded MAIN.md for the persona to import"
    fi

    if [ "$DRY_RUN" = "1" ]; then
        s_note "status   skipped — a dry run changed nothing to report on"
    else
        distill_status
    fi

    echo
    ok "setup done"
    explain \
        "Backfill the last week now:  chez distill --since 7d" \
        "Preview without paying:      chezdistill -n" \
        "Otherwise the nightly job runs at 01:00."
    return 0
}

# _distill_count ARG — an optional numeric argument, or empty.
#
# `--logs -f` and `--runs --stats` must not have their next flag eaten as a
# count, so the lookahead only consumes a token that is entirely digits. Anything
# else is left in place for the parser to handle as the flag it is.
_distill_count() {
    case "${1:-}" in
        '' | *[!0-9]*) return 1 ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# _distill_remote [URL|none] — where this corpus backs up, and changing it.
#
# With no argument it only reports, so it is safe to type when you cannot
# remember. With one it is a network write, so it is confirm-gated like every
# other verb here that reaches outside this machine, and it says what it found at
# the other end BEFORE asking — for a corpus with no identity of its own that
# display is the only check available, so it has to be a human one.
_distill_remote() {
    local arg="${1:-}" repo url populated branch rprofile rid mine
    distill_preflight || return $?
    repo="$(distill_state_dir)"
    mine="$(distill_profile)"

    if [ -z "$arg" ]; then
        url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
        if [ -n "$url" ]; then
            say "this corpus backs up to $url"
        elif distill_corpus_detached; then
            say "this corpus is local only — detached by hand"
        else
            say "this corpus is local only — this Mac is the only copy"
        fi
        [ -n "$(distill_corpus_id)" ] &&
            dim "  identity $(distill_corpus_id) · stamped $(distill_corpus_profile)"
        if [ -n "$url" ]; then
            explain "Move it with: chez distill --remote <url> · stop with: --remote none"
        else
            explain "Attach one with: chez distill --remote <url>"
        fi
        return 0
    fi

    if [ "$arg" = "none" ]; then
        say "would stop pushing this corpus anywhere"
        explain "Nothing is deleted and nothing is rewritten — re-attach with the same command."
        [ "$DRY_RUN" = "1" ] && return 0
        _distill_confirm "Detach it?" || {
            info "aborted — nothing changed"
            return 0
        }
        distill_state_repo_init >/dev/null || true
        distill_remote_detach
        return 0
    fi

    say "would back this Mac's corpus up to $arg"
    read -r populated branch rprofile rid <<<"$(distill_remote_survey "$arg")"
    if [ "${populated:-0}" = "1" ]; then
        dim "  found a corpus there: ${rprofile:-no profile stamp} · ${rid:-no identity} · branch ${branch:-?}"
        if [ -n "$rprofile" ] && [ -n "$mine" ] && [ "$rprofile" != "$mine" ]; then
            fail "that corpus is stamped $rprofile and this is a $mine Mac — refusing"
            return 1
        fi
        [ -z "$rid" ] &&
            explain \
                "It carries no identity yet, so nothing can check it for you." \
                "Confirm it is yours before saying yes — this is the only check there is."
    else
        dim "  nothing there yet — this Mac's corpus becomes the corpus"
    fi

    [ "$DRY_RUN" = "1" ] && {
        dim "dry-run — stopping before the first write"
        return 0
    }
    _distill_confirm "Attach it?" || {
        info "aborted — nothing changed"
        return 0
    }

    distill_remote_attach "$arg" || return 1
    distill_render_all
    return 0
}

_distill_main() {
    local mode=run count="" follow=0 remote=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --setup) mode=setup ;;
            --status) mode=status ;;
            --render) mode=render ;;
            --undo) mode=undo ;;
            --stats) mode=stats ;;
            --runs)
                mode=runs
                if _distill_count "${2:-}" >/dev/null; then
                    count="$2"
                    shift
                fi
                ;;
            --runs=*) mode=runs count="${1#--runs=}" ;;
            --logs)
                mode=logs
                if _distill_count "${2:-}" >/dev/null; then
                    count="$2"
                    shift
                fi
                ;;
            --logs=*) mode=logs count="${1#--logs=}" ;;
            --remote)
                mode=remote
                # Same lookahead as --runs/--logs: a value only if it is one.
                case "${2:-}" in
                    "" | -*) ;;
                    *)
                        remote="$2"
                        shift
                        ;;
                esac
                ;;
            --remote=*) mode=remote remote="${1#--remote=}" ;;
            -f | --follow) follow=1 ;;
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

    if [ -n "$count" ] && ! _distill_count "$count" >/dev/null; then
        fail "--$mode takes a number of lines, not '$count'"
        return 2
    fi

    # Following anything but the log means nothing, and quietly ignoring a flag
    # someone typed is how `chez distill -f` becomes a bug report about a job that
    # "stopped streaming".
    if [ "$follow" = "1" ] && [ "$mode" != "logs" ]; then
        fail "-f/--follow only applies to --logs"
        return 2
    fi

    if [ "$mode" = "setup" ]; then
        _distill_setup
        return $?
    fi
    if [ "$mode" = "undo" ]; then
        _distill_undo
        return $?
    fi
    if [ "$mode" = "remote" ]; then
        _distill_remote "$remote"
        return $?
    fi

    # The read-only modes, dispatched before preflight. None of them needs the
    # corpus remote to be right, and --logs in particular has to work on a machine
    # whose remote is what's wrong — that is exactly when you want the log.
    case "$mode" in
        status)
            distill_status
            return 0
            ;;
        stats)
            distill_stats
            return 0
            ;;
        runs)
            distill_runs "${count:-14}"
            return 0
            ;;
        logs)
            distill_logs "${count:-50}" "$follow"
            return 0
            ;;
    esac

    echo
    printf '%s%s%s  %sDistilling Claude Code conversations%s\n' \
        "$CYAN" "$NODE" "$RESET" "$BOLD" "$RESET"
    explain \
        "Read what you and Claude worked out since the last run, and write it up." \
        "Only entries seen in two separate sessions reach MAIN.md."

    distill_preflight || return 1

    case "$mode" in
        render)
            distill_render_all
            ok "rendered the memory tier from the corpus"
            ;;
        run)
            distill_run_daily || return 1
            ok "memory tier updated"
            ;;
    esac
    return 0
}

# Tests source this file to exercise the pure helpers, so only run when executed.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
    _distill_main "$@"
fi
