#!/usr/bin/env bash
# distill.sh — chezdistill: distil Claude Code conversations into the memory tier
# every future session loads, and the reports you read in the vault.
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
# shellcheck source=../lib/chezmoi-data.sh
. "$_DIR/../lib/chezmoi-data.sh"
# shellcheck source=../lib/modules.sh
. "$_DIR/../lib/modules.sh"

_distill_help() {
    cat <<'EOF'
usage: chezdistill [--setup] [--weekly] [--since SPEC] [--status] [--render]
                   [--undo] [-n]

Distil recent Claude Code conversations into three places:

  ~/.config/claude/memory     MAIN.md, Topics/, Candidates.md — read by Claude
  ~/.local/state/chezdistill  the extract corpus, Pinned.md, cursor, spend, runs
  the vault's 30-Claude       Daily/, Weekly/, Runs.md — read by you

  (no flags)        run the nightly job now — the same code path launchd uses
  --setup           turn it on for this Mac: migrate an older layout, create the
                    vault folder, enable the module, apply, register the timers.
                    Idempotent, no API calls
  --weekly          run the weekly review and compaction now
  --since SPEC      backfill from a point in time: 7d, 24h, or an ISO timestamp
  --status          where everything lives, MAIN size vs cap, spend, last run
  --render          rebuild MAIN.md, Topics, Candidates and Runs from the
                    corpus; no API calls
  --undo            revert the state repo's last chezdistill commit and
                    re-render the memory tier from it
  -n, --dry-run     show what would be read and run, without calling the model
  -h, --help        this text

The vault is never created by this command — not even by --setup. If it is
missing, the reports are skipped and the memory tier still renders, so Claude
keeps its MAIN.md either way.

Before the module is enabled the `chezdistill` shell verb does not exist yet, so
the very first run goes through the script:
  bash ~/Developer/personal/dotfiles/scripts/bin/distill.sh --setup
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
# `--setup` is the one code path allowed to create the `30-Claude` folder. The
# "creates nothing in the vault" rule exists so a report is never written into a
# vault that is unmounted or was never cloned — a state that looks exactly like an
# empty directory. That guard is the vault + `.obsidian` check, and it stays:
# setup refuses just as hard when either is missing.
#
# The memory dir and the state dir are a different matter: they are ordinary local
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

# _distill_setup_folder — the vault half. 0 = ready · 1 = the vault is not here.
_distill_setup_folder() {
    local vault folder profile
    vault="$(distill_expand "$(distill_cfg vaultPath)")"
    folder="$(distill_cfg folder 30-Claude)"
    profile="$(distill_profile)"

    if [ -z "$vault" ] || [ ! -d "$vault" ]; then
        s_fail "vault    not found at ${vault:-<unset>}"
        explain "Setup never creates the vault. Clone or mount it, then re-run." \
            "The path is per profile${profile:+ (this Mac is '$profile')} —" \
            "src/.chezmoidata/distill.toml decides which vault this is."
        return 1
    fi
    if [ ! -d "$vault/.obsidian" ]; then
        s_fail "vault    $vault has no .obsidian"
        explain "That is an unmounted or half-synced vault, not an empty one." \
            "Open it in Obsidian once, then re-run."
        return 1
    fi
    s_pass "vault    $vault"

    if [ -d "$vault/$folder" ]; then
        s_pass "folder   $folder already exists"
    else
        if ! _distill_confirm "Create $vault/$folder?"; then
            s_warn "folder   $folder not created — the job will keep exiting early"
            return 1
        fi
        run mkdir -p "$vault/$folder" || {
            s_fail "folder   could not create $vault/$folder"
            return 1
        }
        s_pass "folder   created $vault/$folder"
    fi

    if ! git -C "$vault" rev-parse --git-dir >/dev/null 2>&1; then
        s_fail "git      $vault is not a git repo — the reports would never be backed up"
        return 1
    fi
    if [ -z "$(git -C "$vault" remote 2>/dev/null)" ]; then
        s_fail "git      $vault has no remote — the reports would never leave this Mac"
        return 1
    fi
    s_pass "git      vault is a repo with a remote"
    return 0
}

# _distill_setup_migrate — move a pre-split installation into place, once.
#
# The old layout kept everything under the vault's 30-Claude, including the
# extracts, because two machines merged through git. One machine needs no merge,
# so the state comes out of the vault entirely and the memory tier moves next to
# the persona that imports it. Idempotent: with nothing old to find, it is silent.
_distill_setup_migrate() {
    local vault folder old mem state date host f moved=0
    vault="$(distill_expand "$(distill_cfg vaultPath)")"
    folder="$(distill_cfg folder 30-Claude)"
    old="$vault/$folder"
    mem="$(distill_memory_dir)"
    state="$(distill_state_dir)"

    [ -d "$old" ] || return 0
    if [ ! -d "$old/.state" ] && [ ! -f "$old/MAIN.md" ]; then
        s_pass "layout   nothing to migrate"
        return 0
    fi

    s_note "layout   found the old single-folder layout in $old"
    dim "           .state/  →  $state"
    dim "           MAIN.md, Pinned.md, Topics/, Inbox/  →  $mem"
    if ! _distill_confirm "Move them?"; then
        s_warn "layout   left in place — the job would start from an empty corpus"
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        dim "dry-run \$ migrate $old"
        return 0
    fi

    mkdir -p "$mem" "$state" || {
        s_fail "layout   could not create $mem or $state"
        return 1
    }

    if [ -d "$old/.state" ]; then
        for f in "$old"/.state/*; do
            [ -e "$f" ] || continue
            case "$(basename "$f")" in
                extracts | spend | runs | cursor-*.json) continue ;;
            esac
            cp -R "$f" "$state/" 2>/dev/null || true
        done
        # extracts/<date>/<host>.json → extracts/<date>.json. With more than one
        # host the local one wins: the others' transcripts are gone anyway, and
        # merging two machines' extracts is not worth a conflict here.
        host="$(hostname -s)"
        for date in "$old"/.state/extracts/*/; do
            [ -d "$date" ] || continue
            f="$date/$host.json"
            [ -f "$f" ] || f="$(/usr/bin/find "$date" -name '*.json' | sort | head -1)"
            [ -n "$f" ] && [ -f "$f" ] || continue
            mkdir -p "$state/extracts"
            cp -f "$f" "$state/extracts/$(basename "${date%/}").json"
        done
        # One file per machine collapses into one file, oldest first.
        for f in spend runs; do
            [ -d "$old/.state/$f" ] || continue
            cat "$old"/.state/"$f"/*.jsonl 2>/dev/null |
                jq -s -c 'sort_by(.t)[]' >"$state/$f.jsonl" 2>/dev/null || true
        done
        f="$old/.state/cursor-$host.json"
        [ -f "$f" ] && cp -f "$f" "$state/cursor.json"
        # The fingerprint that makes an already-distilled day free used to be
        # "<host>  <hash>", one line per contributing machine. Left in the old
        # format nothing ever matches, and the next run silently re-narrates
        # every migrated day — one paid model call each.
        for f in "$state"/narratives/*.sources; do
            [ -f "$f" ] || continue
            awk '{print $NF}' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
        done
        moved=1
    fi

    [ -f "$old/MAIN.md" ] && cp -f "$old/MAIN.md" "$mem/MAIN.md" && moved=1
    # Pinned.md follows the inputs, not the output — see distill_pinned_file.
    for f in "$old/Pinned.md" "$mem/Pinned.md"; do
        [ -f "$f" ] || continue
        [ -f "$(distill_pinned_file)" ] || cp -f "$f" "$(distill_pinned_file)"
        moved=1
    done
    [ -d "$old/Topics" ] && cp -R "$old/Topics" "$mem/" && moved=1
    [ -f "$old/Inbox/Candidates.md" ] &&
        cp -f "$old/Inbox/Candidates.md" "$mem/Candidates.md" && moved=1

    distill_state_repo_init && distill_commit_local "chore(distill): migrate to the split layout"

    if [ "$moved" -eq 1 ]; then
        s_pass "layout   migrated — the old copies are still in $old"
        explain "Nothing was deleted. Once a run looks right, remove the old" \
            "MAIN.md, Pinned.md, Topics/, Inbox/ and .state/ from the vault by hand."
    fi
    return 0
}

# _distill_setup_module — put claudeDistiller into the chezmoi module list.
# Edits the single `modules = [...]` line rather than re-running `chezmoi init`:
# init re-derives every other saved answer, and this has to change exactly one.
# The edit itself lives in scripts/lib/modules.sh, shared with chezup's
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
        explain "Turn it on by hand instead: chezsetup, and tick claudeDistiller."
        return 1
    fi
    if ! grep -q '^[[:space:]]*modules[[:space:]]*=' "$cfg"; then
        s_fail "module   no 'modules =' line in $cfg"
        explain "Turn it on by hand instead: chezsetup, and tick claudeDistiller."
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
    # Record it as offered too, so chezup's gate stays quiet about a module
    # that has just been answered here.
    modules_write_list "$cfg" modulesSeen $seen || true
    s_pass "module   claudeDistiller enabled"
    return 3
}

# _distill_setup_agents — the launchd half. The plists are rendered by an apply,
# and hook 06 registers them; 3 means "they are not on disk yet, apply first".
# 0 = both registered · 3 = a plist is missing · 1 = a registration failed.
_distill_setup_agents() {
    local uid rc=0 label plist
    [ "$(uname -s)" = "Darwin" ] || {
        s_note "agents   not macOS — no launchd agents to register"
        return 0
    }
    command -v launchctl >/dev/null 2>&1 || {
        s_warn "agents   launchctl not on PATH"
        return 1
    }
    uid="$(id -u)"
    for label in nightly weekly; do
        plist="$HOME/Library/LaunchAgents/no.mlz.chezdistill.$label.plist"
        if [ ! -f "$plist" ]; then
            s_warn "agents   $label plist not rendered yet"
            [ "$rc" -eq 1 ] || rc=3
            continue
        fi
        if launchctl print "gui/$uid/no.mlz.chezdistill.$label" >/dev/null 2>&1; then
            s_pass "agents   $label registered"
            continue
        fi
        if run launchctl bootstrap "gui/$uid" "$plist" 2>/dev/null; then
            s_pass "agents   $label registered"
        else
            s_warn "agents   could not register $label"
            rc=1
        fi
    done
    return "$rc"
}

_distill_setup() {
    local folder_rc module_rc agents_rc needs_apply=0 profile

    echo
    printf '%s%s%s  %sSetting up chezdistill on this Mac%s\n' \
        "$CYAN" "$NODE" "$RESET" "$BOLD" "$RESET"
    explain \
        "Creates the vault folder, turns on the module, and registers the timers." \
        "It never creates the vault itself, and it makes no API calls."

    s_section "chezdistill setup"

    # Stated before anything is created, because it decides where: a work Mac
    # and a personal one distil into different vaults on purpose.
    profile="$(distill_profile)"
    if [ -n "$profile" ]; then
        s_pass "profile  $profile"
    else
        s_note "profile  unset — using the base config"
    fi

    _distill_setup_folder
    folder_rc=$?

    [ "$folder_rc" -eq 0 ] && _distill_setup_migrate

    _distill_setup_module
    module_rc=$?
    [ "$module_rc" -eq 3 ] && needs_apply=1

    # An apply is also what puts the plists on disk, so a machine whose module
    # was already on but never applied gets offered the same fix.
    _distill_setup_agents
    agents_rc=$?
    [ "$agents_rc" -eq 3 ] && needs_apply=1

    if [ "$needs_apply" -eq 1 ]; then
        s_note "apply    needed — the plists and the MAIN.md import render there"
        if _distill_confirm "Run chezmoi apply now?"; then
            run chezmoi apply --force || s_warn "apply    chezmoi apply reported an error"
            _distill_setup_agents || true
        else
            s_warn "apply    skipped — run chezup before the timers can fire"
        fi
    fi

    if [ "$folder_rc" -ne 0 ]; then
        echo
        fail "setup incomplete — the vault is not ready on this machine"
        return 1
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
        "Backfill the last week now:  chezdistill --since 7d" \
        "Preview without paying:      chezdistill -n" \
        "Otherwise the nightly job runs at 01:00, the weekly one Sunday at 02:00."
    return 0
}

_distill_main() {
    local mode=run

    while [ $# -gt 0 ]; do
        case "$1" in
            --setup) mode=setup ;;
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

    if [ "$mode" = "setup" ]; then
        _distill_setup
        return $?
    fi
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

    distill_preflight || return 1

    case "$mode" in
        render)
            distill_render_all
            distill_render_dailies
            distill_have_vault && distill_render_runs
            ok "rendered the memory tier and every vault note from the corpus"
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
