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
# shellcheck source=../lib/chezmoi-data.sh
. "$_DIR/../lib/chezmoi-data.sh"

_distill_help() {
    cat <<'EOF'
usage: chezdistill [--setup] [--weekly] [--since SPEC] [--status] [--render]
                   [--undo] [-n]

Distil recent Claude Code conversations into ~/Documents/TheArchive/30-Claude:
a daily report, a weekly review, a Runs.md log of every run from every machine,
and a size-capped MAIN.md that is loaded into every future session.

  (no flags)        run the nightly job now — the same code path launchd uses
  --setup           turn it on for this Mac: create the vault folder, enable the
                    module, apply, register the timers. Idempotent, no API calls
  --weekly          run the weekly review and compaction now
  --since SPEC      backfill from a point in time: 7d, 24h, or an ISO timestamp
  --status          preflight, MAIN size vs cap, unclassified origins, spend,
                    last run
  --render          rebuild MAIN.md, Inbox, Topics and Runs from the ledger; no
                    API calls
  --undo            revert the vault's most recent chezdistill commit
  -n, --dry-run     show what would be read and run, without calling the model
  -h, --help        this text

The vault is never created by this command — not even by --setup. If it is
missing, the job exits without doing anything; clone or mount it first.

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

# ─── Setup ────────────────────────────────────────────────────────────────────
#
# `--setup` is the one code path allowed to create the `30-Claude` folder. The
# "creates nothing" rule exists so a report is never written into a vault that is
# unmounted or was never cloned — a state that looks exactly like an empty
# directory. That guard is the vault + `.obsidian` check, and it stays: setup
# refuses just as hard when either is missing. Preflight itself is unchanged, so
# the nightly job still creates nothing.

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
    local vault folder
    vault="$(distill_expand "$(distill_cfg vaultPath)")"
    folder="$(distill_cfg folder 30-Claude)"

    if [ -z "$vault" ] || [ ! -d "$vault" ]; then
        s_fail "vault    not found at ${vault:-<unset>}"
        explain "Setup never creates the vault. Clone or mount TheArchive, then re-run."
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
        s_fail "git      $vault is not a git repo — the two machines merge through it"
        return 1
    fi
    if [ -z "$(git -C "$vault" remote 2>/dev/null)" ]; then
        s_fail "git      $vault has no remote — nothing would ever reach the other Mac"
        return 1
    fi
    s_pass "git      vault is a repo with a remote"
    return 0
}

# _distill_setup_module — put claudeDistiller into the chezmoi module list.
# Edits the single `modules = [...]` line rather than re-running `chezmoi init`:
# init re-derives every other saved answer, and this has to change exactly one.
# 0 = already on · 3 = turned on now (an apply is needed) · 1 = could not.
_distill_setup_module() {
    local cfg line old new
    if ! command -v chezmoi >/dev/null 2>&1; then
        s_warn "module   chezmoi is not on PATH — skipping the module check"
        return 1
    fi
    if cm_has_module "$(cm_data_json)" claudeDistiller; then
        s_pass "module   claudeDistiller is enabled"
        return 0
    fi

    cfg="${CHEZMOI_CONFIG_FILE:-$HOME/.config/chezmoi/chezmoi.toml}"
    if [ ! -w "$cfg" ]; then
        s_fail "module   claudeDistiller is off, and $cfg is not writable"
        explain "Turn it on by hand instead: chezsetup, and tick claudeDistiller."
        return 1
    fi

    line="$(grep -n '^[[:space:]]*modules[[:space:]]*=' "$cfg" | head -1)"
    if [ -z "$line" ]; then
        s_fail "module   no 'modules =' line in $cfg"
        explain "Turn it on by hand instead: chezsetup, and tick claudeDistiller."
        return 1
    fi
    # Rewrite the whole line, indent included, so the edit is byte-identical to
    # what the wizard would have written.
    old="${line#*:}"
    case "$old" in
        *"[]" | *"[ ]")
            new="$(printf '%s' "$old" |
                sed 's/\[[[:space:]]*\][[:space:]]*$/["claudeDistiller"]/')"
            ;;
        *)
            new="$(printf '%s' "$old" |
                sed 's/][[:space:]]*$/, "claudeDistiller"]/')"
            ;;
    esac

    s_note "module   claudeDistiller is off in $cfg"
    dim "           $old"
    dim "        →  $new"
    if ! _distill_confirm "Add claudeDistiller to the module list?"; then
        s_warn "module   left off — nothing else here will take effect"
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        dim "dry-run \$ edit $cfg"
    else
        # ed-style in-place rewrite of exactly the one line found above.
        awk -v n="${line%%:*}" -v repl="$new" \
            'NR == n { print repl; next } { print }' \
            "$cfg" >"$cfg.chezdistill.tmp" &&
            mv "$cfg.chezdistill.tmp" "$cfg" || {
            rm -f "$cfg.chezdistill.tmp"
            s_fail "module   could not rewrite $cfg"
            return 1
        }
    fi
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
    local folder_rc module_rc agents_rc needs_apply=0

    echo
    printf '%s%s%s  %sSetting up chezdistill on this Mac%s\n' \
        "$CYAN" "$NODE" "$RESET" "$BOLD" "$RESET"
    explain \
        "Creates the vault folder, turns on the module, and registers the timers." \
        "It never creates the vault itself, and it makes no API calls."

    s_section "chezdistill setup"

    _distill_setup_folder
    folder_rc=$?

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

    # DISTILL_ROOT is exported by preflight, and only by preflight — everything
    # below reads it, and it now has a folder to find.
    if ! distill_preflight >/dev/null 2>&1 && [ "$DRY_RUN" != "1" ]; then
        echo
        fail "setup incomplete — preflight still refuses this vault"
        distill_status
        return 1
    fi

    # Seed MAIN.md from the (usually empty) ledger. The apply above rewrote the
    # global persona to @-import it, and an import that resolves to nothing is a
    # rough edge in every session until the first nightly run. Costs no API call.
    if [ "$DRY_RUN" = "1" ]; then
        s_note "render   skipped — a dry run has nothing to render from"
    elif [ -f "$DISTILL_ROOT/MAIN.md" ]; then
        s_pass "render   MAIN.md is present"
    else
        distill_render_main
        distill_render_inbox
        s_pass "render   seeded an empty MAIN.md for the persona to import"
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
            distill_render_runs
            ok "rendered MAIN.md, Inbox, Topics and Runs from the ledger"
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
