#!/usr/bin/env bash
# distill.sh — the chezdistill engine: harvest Claude Code transcripts, render
# the memory tier Claude loads, and write the reports you read.
#
# Three destinations, because the three have nothing in common:
#   DISTILL_MEMORY  ~/.config/claude/memory — MAIN.md, Pinned.md, Topics/,
#                   Candidates.md. Read by Claude, so it must resolve whether or
#                   not the vault happens to be mounted.
#   DISTILL_STATE   ~/.local/state/chezdistill — the extract corpus, cursor, spend,
#                   run log. The extracts ARE the memory: every rule, hit count
#                   and date is derived from them on each render.
#   DISTILL_ROOT    the vault's 30-Claude — Daily/, Weekly/, Runs.md. Reports for
#                   a human, in the app built to read them.
#
# Design principle: the model extracts and narrates, bash decides and writes.
# Every judgement — hit counts, what earns a place in MAIN, what gets demoted —
# is computed here from the extract corpus, so a re-run of a day already
# distilled is a no-op. No model invocation in this file has write access.
# shellcheck disable=SC2034,SC2329

[ -n "${__DOTFILES_DISTILL_SH:-}" ] && return 0
__DOTFILES_DISTILL_SH=1

# ─── Config ───────────────────────────────────────────────────────────────────

_DISTILL_CFG=""

# distill_config — the `.distill` table from .chezmoidata, fetched once.
distill_config() {
    if [ -z "$_DISTILL_CFG" ]; then
        if [ -n "${DISTILL_CONFIG_JSON:-}" ]; then
            _DISTILL_CFG="$DISTILL_CONFIG_JSON"
        else
            _DISTILL_CFG="$(chezmoi data --format=json 2>/dev/null |
                jq -c '.distill // {}' 2>/dev/null)"
        fi
        [ -n "$_DISTILL_CFG" ] || _DISTILL_CFG='{}'
    fi
    printf '%s\n' "$_DISTILL_CFG"
}

# distill_cfg KEY [DEFAULT] — one scalar.
distill_cfg() {
    local key="$1" fallback="${2:-}" out
    out="$(distill_config | jq -r --arg k "$key" '.[$k] // empty')"
    [ -n "$out" ] && printf '%s\n' "$out" || printf '%s\n' "$fallback"
}

# distill_cfg_list KEY — one array, newline separated, empty when absent.
distill_cfg_list() {
    distill_config | jq -r --arg k "$1" '(.[$k] // [])[]'
}

# distill_expand PATH — leading ~ only; config paths are ours, not user input.
distill_expand() {
    case "$1" in
        "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
        "~") printf '%s\n' "$HOME" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# ─── Portable date helpers (BSD on macOS, GNU in CI) ──────────────────────────

# distill_iso_ago DAYS — ISO-8601 Z timestamp DAYS in the past.
distill_iso_ago() {
    date -u -v-"$1"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
        date -u -d "$1 days ago" +%Y-%m-%dT%H:%M:%SZ
}

distill_iso_now() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# distill_iso_epoch ISO — seconds since epoch, 0 when unparseable.
distill_iso_epoch() {
    date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null ||
        date -u -d "$1" +%s 2>/dev/null ||
        echo 0
}

# distill_days_since ISO — whole days between ISO and now.
distill_days_since() {
    local then now
    then="$(distill_iso_epoch "$1")"
    now="$(date -u +%s)"
    [ "$then" -gt 0 ] 2>/dev/null || {
        echo 9999
        return 0
    }
    echo $(((now - then) / 86400))
}

# ─── Preflight ────────────────────────────────────────────────────────────────

# distill_can_write DIR — create a file and remove it again.
#
# `[ -w ]` is not enough on macOS. Under TCC the POSIX bits on
# ~/Documents/TheArchive say "writable" and the write syscall is still refused
# with EPERM, because a launchd agent has no Documents access unless it has been
# granted explicitly. That gap is how the 01:00 run spent weeks reporting success
# while every single write failed. Only an actual write tells the truth.
distill_can_write() {
    local dir="$1" probe
    [ -d "$dir" ] || return 1
    probe="$dir/.chezdistill-write-probe.$$"
    : >"$probe" 2>/dev/null || return 1
    rm -f "$probe" 2>/dev/null
    return 0
}

# distill_preflight — every precondition, checked before any processing.
# Always exports DISTILL_MEMORY and DISTILL_STATE; exports DISTILL_VAULT,
# DISTILL_ROOT and DISTILL_VAULT_OK=1 only when the vault is genuinely here.
#
# The vault is required for the reports and for nothing else. An unmounted or
# never-cloned vault looks exactly like an empty directory, so it is still never
# written into and never created — but it no longer stops the run, because the
# memory tier lives on local disk and Claude needs it either way.
# 0 = go · 1 = broken/unwritable (a real failure)
distill_preflight() {
    local vault folder d

    if ! command -v jq >/dev/null 2>&1; then
        fail "jq is required but not on PATH"
        return 1
    fi

    DISTILL_MEMORY="$(distill_expand \
        "$(distill_cfg memoryPath "$HOME/.config/claude/memory")")"
    DISTILL_STATE="$(distill_expand \
        "$(distill_cfg statePath "$HOME/.local/state/chezdistill")")"
    DISTILL_VAULT=""
    DISTILL_ROOT=""
    DISTILL_VAULT_OK=0
    export DISTILL_MEMORY DISTILL_STATE DISTILL_VAULT DISTILL_ROOT DISTILL_VAULT_OK

    # Memory and state are the job's own directories. If they cannot be written
    # there is nothing worth continuing for, so this one IS fatal.
    mkdir -p "$DISTILL_MEMORY" "$DISTILL_STATE" 2>/dev/null || true
    for d in "$DISTILL_MEMORY" "$DISTILL_STATE"; do
        distill_can_write "$d" && continue
        fail "cannot write to $d"
        return 1
    done

    vault="$(distill_expand "$(distill_cfg vaultPath)")"
    folder="$(distill_cfg folder 30-Claude)"

    if [ -z "$vault" ] || [ ! -d "$vault" ]; then
        info "vault not found at ${vault:-<unset>} — skipping the reports"
        return 0
    fi
    if [ ! -d "$vault/.obsidian" ]; then
        info "$vault has no .obsidian — not a vault (unmounted or not cloned yet)"
        return 0
    fi
    if [ ! -d "$vault/$folder" ]; then
        info "$vault/$folder does not exist — create it in Obsidian first"
        return 0
    fi
    if ! distill_can_write "$vault/$folder"; then
        distill_warn "cannot write to $vault/$folder — skipping the reports"
        explain \
            "The POSIX bits allow it, so this is macOS privacy protection:" \
            "a launchd agent has no access to ~/Documents unless it is granted." \
            "System Settings → Privacy & Security → Full Disk Access → add /bin/bash." \
            "Until then the nightly run still writes MAIN.md and the corpus."
        return 0
    fi
    if ! git -C "$vault" rev-parse --git-dir >/dev/null 2>&1; then
        fail "$vault is not a git repo"
        return 1
    fi
    if [ -z "$(git -C "$vault" remote 2>/dev/null)" ]; then
        fail "$vault has no configured git remote"
        return 1
    fi

    DISTILL_VAULT="$vault"
    DISTILL_ROOT="$vault/$folder"
    DISTILL_VAULT_OK=1
    return 0
}

# distill_state_dir — every file no human reads, outside both git remotes.
# distill_memory_dir — what Claude loads. Created on demand: unlike the vault,
# there is nothing here that could be a stale mount point.
#
# Both read the exported value when preflight has run and fall back to the
# configured path when it has not, so a caller that runs before preflight — the
# one-time migration in --setup does — still lands where the config says rather
# than on the built-in default.
distill_state_dir() {
    [ -n "${DISTILL_STATE:-}" ] && {
        printf '%s\n' "$DISTILL_STATE"
        return 0
    }
    distill_expand "$(distill_cfg statePath "$HOME/.local/state/chezdistill")"
}

distill_memory_dir() {
    [ -n "${DISTILL_MEMORY:-}" ] && {
        printf '%s\n' "$DISTILL_MEMORY"
        return 0
    }
    distill_expand "$(distill_cfg memoryPath "$HOME/.config/claude/memory")"
}

# distill_pinned_file — the one hand-written file in the whole pipeline, and the
# only reason the state dir is worth backing up beyond convenience: everything
# else there can be re-derived or re-earned, and this cannot.
#
# It lives with the inputs, not with the output. Everything under the memory dir
# is generated and says so in its own header; a file you are told to edit sitting
# among files you are told never to edit is a trap.
distill_pinned_file() {
    printf '%s/Pinned.md\n' "$(distill_state_dir)"
}

# distill_have_vault — 0 when the reports have somewhere to go.
distill_have_vault() {
    [ "${DISTILL_VAULT_OK:-0}" = "1" ] && [ -n "${DISTILL_ROOT:-}" ]
}

# ─── Harvest ──────────────────────────────────────────────────────────────────

# distill_session_files SINCE_ISO — transcripts that can still hold anything
# newer than SINCE, subagents excluded.
#
# The window is derived from the cursor rather than fixed, because a fixed one
# silently defeats the cursor. A Mac that slept for five days wakes with a
# five-day-old cursor, and `--since 7d` asks for a week outright; either way a
# transcript last written six days ago is exactly the file that must be read,
# and a two-day window drops it without a word. A file's mtime moves whenever a
# turn is appended, so mtime older than the cursor really does mean "nothing new
# in here" — the one day of slack absorbs clock skew and timezone edges.
#
# `find` is shadowed by bfs in this user's interactive shell, hence the full path.
distill_session_files() {
    local root expanded days since="${1:-}"
    days=2
    if [ -n "$since" ]; then
        days="$(distill_days_since "$since")"
        # 9999 is distill_days_since's answer for a timestamp it cannot parse;
        # never let that turn into a scan of every transcript ever written.
        if ! [ "$days" -ge 1 ] 2>/dev/null || [ "$days" -ge 9999 ]; then
            days=1
        fi
        days=$((days + 1))
    fi
    while IFS= read -r root; do
        [ -n "$root" ] || continue
        expanded="$(distill_expand "$root")"
        [ -d "$expanded" ] || continue
        /usr/bin/find "$expanded" -type f -name '*.jsonl' \
            -not -path '*/subagents/*' -mtime -"${DISTILL_MTIME_DAYS:-$days}" 2>/dev/null
    done < <(distill_cfg_list transcriptRoots)
}

# distill_filter FILE SINCE_ISO — the 16x reduction.
# Keeps typed human turns and assistant prose; drops tool traffic, thinking,
# sidechains and harness noise. ISO-8601 Z timestamps compare correctly as
# strings, so no date parsing is needed here.
distill_filter() {
    local file="$1" since="$2"
    jq -c --arg since "$since" '
        select(.timestamp != null and .timestamp > $since)
        | select((.isSidechain // false) | not)
        | select((.isMeta // false) | not)
        | select(.type == "assistant"
                 or (.type == "user" and .promptSource == "typed"))
        | { u: .uuid, t: .timestamp, r: (.message.role // .type),
            s: .sessionId, c: .cwd, g: .gitBranch,
            x: [ (.message.content // [])
                 | if type == "string" then .
                   else (.[] | select(.type == "text") | .text) end ] }
        | select((.x | length) > 0)
        | .x |= map(.[0:4000])
    ' "$file" 2>/dev/null
}

# distill_session_title FILE — the model-generated title; re-emitted, take the last.
distill_session_title() {
    jq -r 'select(.type == "ai-title") | .aiTitle' "$1" 2>/dev/null | tail -1
}

# distill_dedupe — drop entries resumed sessions re-serialise, oldest first.
# Slurps, which is safe only because the filter above has already cut the
# corpus to a few hundred KB per day.
distill_dedupe() {
    jq -s -c 'unique_by(.u) | sort_by(.t) | .[]'
}

# distill_turns — typed human turns in a filtered stream.
distill_turns() {
    jq -s '[.[] | select(.r == "user")] | length'
}

# ─── Model invocation ─────────────────────────────────────────────────────────
#
# Every call here is toolless and writes nothing. The rubric REPLACES the default
# system prompt rather than appending to it: this is a pure extraction task with
# no need for Claude Code's persona or tool guidance, and measured on this install
# it cuts the per-call cost by roughly an order of magnitude ($0.063 → $0.004,
# most of the difference being harness context that is cached and re-read).

# distill_claude MODEL SYSTEM_FILE SCHEMA_FILE PROMPT — payload on stdin.
# Prints the validated structured output; returns 1 on any failure.
distill_claude() {
    local model="$1" sysfile="$2" schemafile="$3" prompt="$4"
    local budget envelope err

    budget="$(distill_cfg maxBudgetUsd 2.0)"

    if [ "${DRY_RUN:-0}" = "1" ]; then
        # To stderr, not stdout: the caller captures this function's stdout as the
        # model's answer, so the notice would be parsed as part of the JSON. It
        # was — `jq: parse error at line 1, column 10` is the width of "dry-run $ "
        # — and every session in a dry run therefore reported "nothing durable".
        dim "dry-run \$ claude -p --model $model --tools \"\" (payload on stdin)" >&2
        echo '{}'
        return 0
    fi

    envelope="$(claude -p \
        --model "$model" \
        --no-session-persistence \
        --tools "" \
        --system-prompt-file "$sysfile" \
        --json-schema "$(cat "$schemafile")" \
        --max-budget-usd "$budget" \
        --output-format json \
        "$prompt" 2>&1)" || {
        distill_fail "claude invocation failed for model $model"
        return 1
    }

    if ! printf '%s' "$envelope" | jq -e . >/dev/null 2>&1; then
        distill_fail "claude returned non-JSON output"
        printf '%s\n' "$envelope" | head -3 >&2
        return 1
    fi

    distill_spend_record "$(printf '%s' "$envelope" | jq -r '.total_cost_usd // 0')"

    if [ "$(printf '%s' "$envelope" | jq -r '.is_error // false')" = "true" ]; then
        err="$(printf '%s' "$envelope" | jq -r '.result // .subtype // "unknown"')"
        distill_fail "claude reported an error: $err"
        return 1
    fi

    printf '%s' "$envelope" | jq -e '.structured_output' 2>/dev/null || {
        distill_fail "claude returned no structured output"
        return 1
    }
}

# ─── Spend ────────────────────────────────────────────────────────────────────
#
# Append-only. The ceiling protects an account quota that `claude -p` shares with
# interactive work, so it is checked in preflight rather than after the fact.

distill_spend_file() {
    printf '%s/spend.jsonl\n' "$(distill_state_dir)"
}

distill_spend_record() {
    local usd="$1" f
    [ -n "$usd" ] || return 0
    case "$usd" in
        0 | 0.0 | null | '') return 0 ;;
    esac
    f="$(distill_spend_file)"
    mkdir -p "$(dirname "$f")"
    printf '{"t":"%s","usd":%s}\n' "$(distill_iso_now)" "$usd" >>"$f"
}

# distill_spend_7d — total spend over the last 7 days.
distill_spend_7d() {
    local since f
    since="$(distill_iso_ago 7)"
    f="$(distill_spend_file)"
    [ -f "$f" ] || {
        echo 0
        return 0
    }
    jq -s --arg since "$since" \
        '[.[] | select(.t > $since) | .usd] | add // 0' "$f" 2>/dev/null || echo 0
}

# distill_spend_ok — the rolling ceiling, checked in preflight so a runaway
# cannot quietly bill for a week before anyone notices.
distill_spend_ok() {
    local spent ceiling
    spent="$(distill_spend_7d)"
    ceiling="$(distill_cfg maxSpendUsd7d 15.0)"
    if jq -n --argjson s "$spent" --argjson c "$ceiling" -e '$s >= $c' >/dev/null 2>&1; then
        distill_fail "7-day spend \$$spent has reached the \$$ceiling ceiling — refusing to start"
        return 1
    fi
    return 0
}

# ─── Run log ──────────────────────────────────────────────────────────────────
#
# One record per run, appended to runs.jsonl and rendered into Runs.md by bash,
# like every other note here. The point is the runs nobody watches: a nightly job
# that skipped every session at 01:00 otherwise leaves its only trace in a launchd
# log, and "nothing ran" and "nothing was worth keeping" have to stay
# distinguishable.
#
# The record is written even when the run failed. The commit may not happen (a
# gitleaks hit blocks it), but the file is append-only, so the next run that does
# commit carries the failed run's record with it.

distill_run_file() {
    printf '%s/runs.jsonl\n' "$(distill_state_dir)"
}

# distill_run_all — every record, oldest first.
distill_run_all() {
    cat "$(distill_run_file)" 2>/dev/null
}

# distill_run_begin MODE — open the record for this run.
distill_run_begin() {
    _DISTILL_RUN_MODE="$1"
    _DISTILL_RUN_START="$(distill_iso_now)"
    _DISTILL_RUN_EPOCH="$(date -u +%s)"
    _DISTILL_RUN_SINCE=""
    _DISTILL_EVENTS="$(mktemp)"
    _DISTILL_SESSIONS="$(mktemp)"
    DISTILL_RUN_SEEN=0
    DISTILL_RUN_KEPT=0
    DISTILL_RUN_ITEMS=0
    DISTILL_RUN_DATES=""
    DISTILL_RUN_WEEK=""
}

# distill_event LEVEL TEXT — remember a line for the record. A no-op outside a
# run, so --status and --render can call the same helpers.
distill_event() {
    [ -f "${_DISTILL_EVENTS:-}" ] || return 0
    printf '%s\t%s\n' "$1" "$2" >>"$_DISTILL_EVENTS"
}

# distill_warn / distill_fail — say it on the console AND keep it for Runs.md.
# Nobody reads the launchd log of the Mac that was asleep.
distill_warn() {
    distill_event warn "$1"
    warn "$1"
}

distill_fail() {
    distill_event fail "$1"
    fail "$1"
}

# distill_run_session NAME TURNS VERDICT ITEMS — why one session was kept or
# skipped. This is what makes a quiet run legible: "7 seen, 0 kept" is alarming
# until you can see that six were under minTurns and cost nothing.
distill_run_session() {
    [ -f "${_DISTILL_SESSIONS:-}" ] || return 0
    jq -nc --arg s "$1" --argjson t "${2:-0}" \
        --arg v "$3" --argjson n "${4:-0}" \
        '{session:$s, turns:$t, verdict:$v, items:$n}' \
        >>"$_DISTILL_SESSIONS"
}

# distill_run_cost — what this run spent, read back from the same spend log the
# rolling ceiling uses rather than counted separately.
distill_run_cost() {
    local f
    f="$(distill_spend_file)"
    [ -f "$f" ] || {
        echo 0
        return 0
    }
    jq -s --arg since "${_DISTILL_RUN_START:-}" \
        '[.[] | select(.t >= $since) | .usd] | add // 0' "$f" 2>/dev/null || echo 0
}

# distill_run_record STATUS — append this run to this machine's log.
distill_run_record() {
    local status="$1" f notes sessions cost main
    f="$(distill_run_file)"
    mkdir -p "$(dirname "$f")"

    notes="$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")
                          | {level: .[0], text: (.[1] // "")})' \
        <"${_DISTILL_EVENTS:-/dev/null}" 2>/dev/null)"
    sessions="$(jq -s -c '.' <"${_DISTILL_SESSIONS:-/dev/null}" 2>/dev/null)"
    cost="$(distill_run_cost)"
    main=0
    [ -f "$(distill_memory_dir)/MAIN.md" ] &&
        main="$(wc -c <"$(distill_memory_dir)/MAIN.md" | tr -d ' ')"

    jq -nc \
        --arg t "${_DISTILL_RUN_START:-$(distill_iso_now)}" \
        --arg end "$(distill_iso_now)" \
        --argjson dur "$(($(date -u +%s) - ${_DISTILL_RUN_EPOCH:-0}))" \
        --arg mode "${_DISTILL_RUN_MODE:-daily}" \
        --arg trigger "${DISTILL_TRIGGER:-manual}" \
        --arg vault "$(distill_have_vault && printf ok || printf skipped)" \
        --arg since "${_DISTILL_RUN_SINCE:-}" \
        --arg dates "${DISTILL_RUN_DATES:-}" \
        --argjson seen "${DISTILL_RUN_SEEN:-0}" \
        --argjson kept "${DISTILL_RUN_KEPT:-0}" \
        --argjson items "${DISTILL_RUN_ITEMS:-0}" \
        --argjson cost "${cost:-0}" \
        --argjson main "${main:-0}" \
        --arg status "$status" \
        --argjson notes "${notes:-[]}" \
        --argjson sessions "${sessions:-[]}" \
        '{t:$t, end:$end, dur:$dur, mode:$mode, trigger:$trigger, vault:$vault,
          since:$since, status:$status, items:$items, cost:$cost,
          main_bytes:$main,
          dates:($dates | split(" ") | map(select(length > 0))),
          sessions:{seen:$seen, kept:$kept, detail:$sessions},
          notes:$notes}' >>"$f"
}

# distill_run_prune — the log is a running record, not an archive.
distill_run_prune() {
    local f cutoff
    f="$(distill_run_file)"
    [ -f "$f" ] || return 0
    cutoff="$(distill_iso_ago "$(distill_cfg runRetentionDays 90)")"
    jq -c --arg c "$cutoff" 'select(.t >= $c)' "$f" >"$f.tmp" 2>/dev/null &&
        mv "$f.tmp" "$f" || rm -f "$f.tmp"
}

# distill_last_run — the newest record, one JSON line.
distill_last_run() {
    distill_run_all | jq -s -c 'sort_by(.t) | last // empty' 2>/dev/null
}

# distill_render_runs — the operator's view: what ran, when, what it cost and
# what went wrong. Deterministic like every other render: same records in,
# byte-identical file out.
distill_render_runs() {
    local out="${1:-$DISTILL_ROOT/Runs.md}" shown week
    distill_have_vault || [ -n "${1:-}" ] || return 0
    shown="$(distill_cfg runsShown 30)"
    week="$(distill_iso_ago 7)"
    mkdir -p "$(dirname "$out")"

    {
        printf '<!-- Generated by chezdistill. Times are UTC. -->\n\n'
        printf '# Runs\n\n'
        printf 'Every nightly and weekly run on this Mac.\n\n'

        printf '## Last 7 days\n\n'
        distill_run_all | jq -s -r --arg since "$week" '
            [.[] | select(.t >= $since)] as $r
            | if ($r | length) == 0 then "No runs in the last 7 days."
              else
                "- \($r | length) run(s): \([$r[] | select(.status == "ok")] | length) ok, \([$r[] | select(.status != "ok")] | length) failed",
                "- \([$r[].sessions.kept] | add // 0) of \([$r[].sessions.seen] | add // 0) session(s) distilled, \([$r[].items] | add // 0) item(s)",
                "- $\(([$r[].cost] | add // 0) * 100 | round / 100) spent",
                (([$r[] | select(.vault == "skipped")] | length) as $skipped
                 | if $skipped > 0
                   then "- ⚠ \($skipped) run(s) could not write to the vault — reports skipped that night"
                   else empty end)
              end'

        printf '\n## Recent runs\n\n'
        printf '| Ended | Mode | Sessions | Items | Cost | MAIN | Result |\n'
        printf '|---|---|---|---|---|---|---|\n'
        distill_run_all | jq -s -r --argjson n "$shown" '
            sort_by(.t) | reverse | .[0:$n][]
            | ([(.notes // [])[] | select(.level == "fail")] | length) as $f
            | ([(.notes // [])[] | select(.level == "warn")] | length) as $w
            | "| \(.end[0:16] | sub("T"; " ")) | \(.mode) | \(.sessions.kept)/\(.sessions.seen) | \(.items) | $\(.cost * 100 | round / 100) | \((.main_bytes / 1024 * 10 | round / 10))K | "
              + (if .status != "ok" then "**failed**"
                 elif $f > 0 then "ok, \($f) error(s)"
                 elif $w > 0 then "ok, \($w) warning(s)"
                 else "ok" end)
              + " |"'

        printf '\n## Problems\n\n'
        distill_run_all | jq -s -r --arg since "$week" '
            [.[] | select(.t >= $since) | . as $r | (.notes // [])[]
             | "- \($r.end[0:16] | sub("T"; " ")) · \($r.mode) · **\(.level)** — \(.text)"]
            | if length == 0 then "Nothing reported in the last 7 days."
              else (sort | reverse | .[]) end'

        printf '\n## Last run in detail\n\n'
        distill_run_all | jq -s -r '
            (sort_by(.t) | last) as $r
            | if $r == null then "No runs recorded yet."
              else
                "*\($r.end[0:16] | sub("T"; " ")) · \($r.mode) · \($r.trigger) · \($r.dur)s · reports \($r.vault // "?") · read since \(if $r.since == "" then "?" else $r.since end)*",
                "",
                (if ($r.sessions.detail | length) == 0
                 then "No sessions were in the window."
                 else ($r.sessions.detail[]
                       | "- `\(.session[0:8])` · \(.turns) turn(s) · \(.verdict)"
                         + (if .items > 0 then " · \(.items) item(s)" else "" end))
                 end)
              end'
        printf '\n'
    } >"$out"
}

# distill_run_message STATUS — the commit subject for this run.
distill_run_message() {
    local dates="${DISTILL_RUN_DATES:-}"
    if [ "$1" != "ok" ]; then
        printf 'chore(distill): failed %s run\n' "${_DISTILL_RUN_MODE:-daily}"
    elif [ "${_DISTILL_RUN_MODE:-daily}" = "weekly" ]; then
        printf 'chore(distill): weekly review %s\n' "${DISTILL_RUN_WEEK:-}"
    elif [ -n "${dates// /}" ]; then
        printf 'chore(distill): report for%s\n' "$dates"
    else
        printf 'chore(distill): run log\n'
    fi
}

# distill_run_end RC — close the record and publish. This is the ONLY place
# anything is committed: a run that failed half way still has to leave its record
# behind, and putting the record in the same commit as the report is what keeps
# the two from disagreeing about what happened.
distill_run_end() {
    local rc="$1" status="ok" msg

    [ "$rc" -eq 0 ] || status="failed"
    # A body can return 0 while individual writes failed underneath it — which is
    # exactly how a run where nothing reached disk was recorded as "ok". Any
    # fail-level event this run recorded overrides the body's own verdict.
    if [ -f "${_DISTILL_EVENTS:-}" ] &&
        grep -q '^fail	' "${_DISTILL_EVENTS}" 2>/dev/null; then
        status="failed"
    fi
    msg="$(distill_run_message "$status")"

    if [ "${DRY_RUN:-0}" != "1" ]; then
        distill_run_record "$status"
        distill_run_prune
        distill_have_vault && distill_render_runs
    fi
    rm -f "${_DISTILL_EVENTS:-}" "${_DISTILL_SESSIONS:-}"
    _DISTILL_EVENTS=""
    _DISTILL_SESSIONS=""

    distill_guard_secrets || return 1
    distill_sync_skills
    distill_commit_local "$msg"
    distill_have_vault && distill_git_push "$msg"
    return 0
}

# ─── Ledger ───────────────────────────────────────────────────────────────────
#
# There is one source of truth and it is the extract corpus: `extracts/<date>.json`,
# one file per day. Everything the renderer needs — the rule, its detail, hit
# counts, first and last seen — is DERIVED from it on every run rather than stored
# alongside it. Deriving is what makes `--since 7d`, `--render` and a repeated
# nightly run all safe to fire at will; a stored count would double on the second
# read of a day.
#
# An entry's identity is a hash of its normalised text, so the same fact extracted
# from two conversations collapses to one entry with two sightings.

distill_sha() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | cut -c1-12
    else
        sha256sum | cut -c1-12
    fi
}

# distill_entry_id TEXT — stable across re-runs.
distill_entry_id() {
    printf '%s' "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr -s '[:space:]' ' ' |
        sed -e 's/^ *//' -e 's/[ .,;:!?]*$//' |
        distill_sha
}

distill_extracts_dir() {
    printf '%s/extracts\n' "$(distill_state_dir)"
}

# distill_derive — the single source of truth for every rendering decision.
# Aggregates the extract corpus into one NDJSON stream:
#   {id, text, kind, topic, hits, first_seen, last_seen}
#
# `hits` counts DISTINCT sessions, which is what the promotion gate is really
# asking: has this come up more than once, or is it one conversation's reading?
distill_derive() {
    local ex
    ex="$(distill_extracts_dir)"
    [ -d "$ex" ] || return 0

    /usr/bin/find "$ex" -type f -name '*.json' 2>/dev/null |
        while IFS= read -r f; do
            jq -c --arg date "$(basename "$f" .json)" \
                '.items[]? | {text, detail, kind, topic, session, date:$date}' \
                "$f" 2>/dev/null
        done |
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            printf '%s\n' "$item" |
                jq -c --arg id "$(distill_entry_id \
                    "$(printf '%s' "$item" | jq -r '.text')")" '. + {id:$id}'
        done |
        jq -s -c '
            group_by(.id)[]
            | { id: .[0].id,
                text: .[0].text,
                detail: (.[0].detail // ""),
                kind: .[0].kind,
                topic: (.[0].topic // "General"),
                hits: ([.[].session] | unique | length),
                last_seen: ([.[].date] | max),
                first_seen: ([.[].date] | min) }'
}

# distill_prune_extracts — age out the sensitive half of an old extract without
# touching the half the renderer needs.
#
# Deleting old extracts would be the obvious reading of `extractRetentionDays`,
# and it would be wrong: the extracts ARE the memory. `hits` and `first_seen` are
# derived from them on every render, so deleting a 90-day-old sighting drops an
# established rule back below the promotion gate and evicts it from MAIN.md — the
# corpus would silently forget exactly the rules that have been true longest.
#
# What actually deserves an expiry is the quoted `evidence` and the local `cwd`
# path. Those are dropped; text, detail, kind, topic, session and date stay, so
# the rendered memory is unchanged and a re-render is still byte-identical.
# `origin` and `host` go too — dead fields from the two-machine layout.
distill_prune_extracts() {
    local days cutoff f date tmp
    days="$(distill_cfg extractRetentionDays 90)"
    cutoff="$(date -u -v-"$days"d +%Y-%m-%d 2>/dev/null ||
        date -u -d "$days days ago" +%Y-%m-%d)"

    for f in "$(distill_extracts_dir)"/*.json; do
        [ -f "$f" ] || continue
        date="$(basename "$f" .json)"
        [ "$date" '<' "$cutoff" ] || continue
        jq -e '[.items[]? | select(has("evidence") or has("cwd")
               or has("origin") or has("host"))] | length > 0' \
            "$f" >/dev/null 2>&1 || continue
        tmp="$f.tmp"
        jq '{items: [.items[]? | del(.evidence, .cwd, .origin, .host)]}' \
            "$f" >"$tmp" 2>/dev/null && mv "$tmp" "$f" || rm -f "$tmp"
    done
}

# ─── Rendering ────────────────────────────────────────────────────────────────
#
# One section, because one machine distilling one person's work has no second
# context to scope against. Rules that only apply somewhere say so in their own
# text, the way a hand-written rule in Pinned.md would.
#
# MAIN.md is rendered, never written by the model. Identical input yields a
# byte-identical file, so a re-render produces no diff and no commit.
#
# Eligibility for MAIN, all derived:
#   hits >= minHits          the promotion gate — one misreading can't become a rule
#   last_seen >= cutoff      still current; stale entries fall back to Topics
#
# Note this differs from the original plan, which demoted on
# "not reinforced for N days AND hits < minHits". That predicate can never fire:
# anything in MAIN already has hits >= minHits by the promotion gate, so the age
# rule would have been dead code and MAIN would only ever have grown. Age alone
# demotes here; `Pinned.md` is the channel for things that must never age out.

_DISTILL_MAIN_HEADING="Learned from past sessions"

distill_eligible() {
    local cutoff minhits
    minhits="$(distill_cfg minHits 2)"
    cutoff="$(date -u -v-"$(distill_cfg demoteAfterDays 21)"d +%Y-%m-%d 2>/dev/null ||
        date -u -d "$(distill_cfg demoteAfterDays 21) days ago" +%Y-%m-%d)"
    distill_derive | jq -c --argjson minhits "$minhits" --arg cutoff "$cutoff" '
        . + { eligible: (.hits >= $minhits
                         and .last_seen >= $cutoff),
              score: (.hits * 100000 + (.last_seen | gsub("-";"") | tonumber % 100000)) }'
}

# The one line in MAIN that points at the tier below it. Every byte here is
# re-read in every session forever, so this is a single pointer at a guessable
# naming scheme rather than a link per rule — per-rule paths measured at roughly
# a sixth of the whole budget.
# `~` rather than the absolute path, everywhere a path is printed INTO MAIN.md:
# every byte here is re-read in every session forever, and the two lines below
# were together spending ~60 of them to say what `~` says. It reads the same to a
# person and to a model.
distill_tilde() {
    case "$1" in
        "$HOME"/*) printf '~%s\n' "${1#"$HOME"}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

_distill_topics_pointer() {
    printf 'Fuller explanations for the rules below live beside this file, in `%s/Topics/<Topic>.md`.\n' \
        "$(distill_tilde "$(distill_memory_dir)")"
}

# distill_render_main [OUTFILE] — deterministic; running it twice is a no-op.
distill_render_main() {
    local out="${1:-$(distill_memory_dir)/MAIN.md}"
    local pinned="$(distill_pinned_file)"
    local cap base tmp chosen line used
    cap="$(distill_cfg mainCapBytes 6144)"
    tmp="$(mktemp)"
    chosen="$(mktemp)"
    mkdir -p "$(dirname "$out")"

    {
        printf '<!-- Generated by chezdistill. Do not edit: edit %s instead. -->\n\n' \
            "$(distill_tilde "$(distill_pinned_file)")"
        _distill_topics_pointer
        if [ -f "$pinned" ]; then
            printf '\n'
            cat "$pinned"
        fi
    } >"$tmp"

    base="$(wc -c <"$tmp" | tr -d ' ')"
    if [ "$base" -gt "$cap" ]; then
        distill_warn "Pinned.md alone exceeds the ${cap}B cap — nothing else will fit"
    fi

    # Reserve the section header up front, even though the section may end up
    # empty: what gets selected depends on the remaining budget, so reserving
    # unconditionally keeps the cap a guarantee rather than an estimate.
    used=$((base + ${#_DISTILL_MAIN_HEADING} + 3))
    # Highest score first, ties broken by id so the order is stable.
    distill_eligible |
        jq -r 'select(.eligible) | [(.score|tostring), .topic, .id, .text] | @tsv' |
        sort -t"$(printf '\t')" -k1,1nr -k3,3 |
        while IFS=$'\t' read -r _ topic id text; do
            line="- $text"
            [ $((used + ${#line} + 1)) -le "$cap" ] || break
            used=$((used + ${#line} + 1))
            printf '%s\t%s\t%s\n' "$topic" "$id" "$text"
        done >"$chosen"

    if [ -s "$chosen" ]; then
        printf '\n## %s\n\n' "$_DISTILL_MAIN_HEADING" >>"$tmp"
        sort -t"$(printf '\t')" -k1,1 -k2,2 "$chosen" |
            while IFS=$'\t' read -r _ _ text; do
                printf -- '- %s\n' "$text" >>"$tmp"
            done
    fi

    rm -f "$chosen"
    if ! mv "$tmp" "$out" 2>/dev/null; then
        rm -f "$tmp"
        distill_fail "could not write $out"
        return 1
    fi

    used="$(wc -c <"$out" 2>/dev/null | tr -d ' ')"
    # Guard the comparison: a failed write leaves this empty, and `[ -le ]` on an
    # empty string is a shell error that reads as "MAIN.md is B, over the cap".
    [ -n "$used" ] || return 1
    [ "$used" -le "$cap" ] || distill_warn "MAIN.md is ${used}B, over the ${cap}B cap"
}

# distill_render_inbox — everything that did not earn a place in MAIN and why.
# Nothing here affects a session; it is the waiting room for the promotion gate.
distill_render_inbox() {
    local out="${1:-$(distill_memory_dir)/Candidates.md}"
    local minhits
    minhits="$(distill_cfg minHits 2)"
    mkdir -p "$(dirname "$out")"
    {
        printf '<!-- Generated by chezdistill. Entries here affect nothing. -->\n\n'
        printf '# Candidates\n\n'
        printf 'Seen in only one session so far. They reach MAIN.md once seen in\n'
        printf 'at least %s distinct session(s).\n' "$minhits"
        printf '\n## Awaiting a second sighting\n\n'
        distill_eligible |
            jq -r --argjson m "$minhits" \
                'select(.hits < $m)
                 | "- \(.text)  ·  \(.hits) hit(s), last seen \(.last_seen)"' |
            sort
        printf '\n## Demoted for age\n\n'
        printf 'Past the promotion gate but not reinforced lately, so they sit in `Topics/` instead.\n\n'
        distill_eligible |
            jq -r --argjson m "$minhits" \
                'select(.hits >= $m and (.eligible | not))
                 | "- \(.text)  ·  \(.hits) hit(s), last seen \(.last_seen)"' |
            sort
    } >"$out"
}

# distill_render_topics — the free tier, and the reason MAIN can afford to be
# terse. MAIN carries the rule (capped at 200 chars by the schema, because every
# byte is re-read in every session); the full `detail` lands here, next to MAIN,
# where it is read only when Claude looks a rule up and length costs nothing.
#
# Everything derived is written, not only what passed the promotion gate: a rule
# waiting for its second sighting is still worth reading once you have gone
# looking for the topic.
# distill_topic_slug TOPIC — the note name a topic is written to and linked by.
# A slash would send the write into a directory that does not exist and a wikilink
# to a note that does not exist; both fail silently, in opposite places.
distill_topic_slug() {
    printf '%s\n' "${1//\//-}"
}

distill_render_topics() {
    local dir="${1:-$(distill_memory_dir)/Topics}"
    local topic slug
    mkdir -p "$dir"

    distill_eligible | jq -r '.topic' | sort -u |
        while IFS= read -r topic; do
            [ -n "$topic" ] || continue
            # The model picks the topic freely, and it has picked names with a
            # slash in them ("Git/GitHub"). Left alone that redirects the write
            # into a directory that does not exist and the topic is silently lost.
            slug="$(distill_topic_slug "$topic")"
            {
                printf '<!-- Generated by chezdistill. -->\n\n# %s\n\n' "$topic"
                # Sorted inside jq: these records are multi-line, and piping
                # them through sort(1) would interleave lines across entries.
                distill_eligible |
                    jq -s -r --arg t "$topic" \
                        '[.[] | select(.topic == $t)]
                         | sort_by(.text)[]
                         | "## \(.text)\n\n\(.detail)\n\n*\(.hits) hit(s) · last seen \(.last_seen)*\n"'
            } >"$dir/$slug.md"
        done
}

# distill_main_diff BEFORE AFTER — the audit trail for the daily report.
distill_main_diff() {
    local before="$1" after="$2"
    diff <(grep '^- ' "$before" 2>/dev/null | sort) \
        <(grep '^- ' "$after" 2>/dev/null | sort) |
        sed -n -e 's/^> - /+ /p' -e 's/^< - /- /p' |
        cut -c1-100
}

# ─── The notes you read ───────────────────────────────────────────────────────
#
# MAIN.md answers "what should Claude know". These answer "what did I decide, and
# what do I still owe" — and they are deliberately NOT behind the promotion gate.
#
# That gate exists because MAIN.md is loaded into every session unattended, so one
# misreading becoming a global rule is a real cost. Neither applies here: a
# decision made once is still a decision, an open thread mentioned once is still
# open, and you are reading these yourself with the judgement to discard a bad
# one. Gating them would mean 37 of 39 items never reach anything you read.

# distill_render_all — every generated note, in dependency order: the memory tier
# first, then the symlink the vault's wikilinks resolve through, then the notes.
# One entry point so a new note cannot be added to the nightly path and forgotten
# in --render.
distill_render_all() {
    distill_render_main
    distill_render_inbox
    distill_render_topics
    distill_link_topics
    distill_render_decisions
    distill_render_threads
    distill_render_index
}

# distill_render_dailies — rebuild every day's report from the corpus.
#
# Free: the narrative is the only model-written part and it is cached beside the
# extracts. Without this a change to the report format only ever reaches days that
# happen to be re-processed, and every older note keeps the shape it was born with
# forever. Not part of the nightly path, which renders the dates it touched.
distill_render_dailies() {
    local f date
    distill_have_vault || return 0
    for f in "$(distill_extracts_dir)"/*.json; do
        [ -f "$f" ] || continue
        date="$(basename "$f" .json)"
        distill_render_daily "$date"
    done
}

# distill_render_decisions — the register, newest decision first. Dated by
# first_seen: a decision belongs to the day it was made, not the last time it
# happened to come up again.
#
# Headings rather than a list, because Obsidian's Outline pane and its heading
# links both work on `##` and neither works on a bullet.
distill_render_decisions() {
    local out="${1:-$DISTILL_ROOT/Decisions.md}" n
    distill_have_vault || [ -n "${1:-}" ] || return 0
    mkdir -p "$(dirname "$out")"
    n="$(distill_derive | jq -s '[.[] | select(.kind == "decisions")] | length')"
    {
        printf -- '---\ntags:\n  - claude/decisions\ndecisions: %s\n---\n\n' "${n:-0}"
        printf '# Decisions\n\n'
        printf '> [!abstract] What was settled, and what it was settled against\n'
        printf '> Newest first. Every decision appears here from the first time it was\n'
        printf '> made — unlike the rules in [[MAIN]], these are not held back waiting\n'
        printf '> for a second sighting.\n\n'
        distill_derive |
            jq -s -r '[.[] | select(.kind == "decisions")]
                | sort_by(.first_seen) | reverse
                | if length == 0 then
                    "*Nothing recorded yet.*"
                  else
                    .[] | "## \(.text)\n\n\(.detail)\n\n> [!quote]- Provenance\n> Decided \(.first_seen) · topic [[\(.topic | gsub("/"; "-"))]] · seen in \(.hits) session(s)\n"
                  end'
    } >"$out"
}

# distill_render_threads — what is still owed. Regenerated from the corpus every
# run rather than accumulated, so it reads as a current list and not an archive:
# an item drops off when it stops being extracted, which is what closing it looks
# like from here.
#
# Checkboxes because Obsidian renders them as real ones. Ticking a box is a note
# to yourself and nothing more — the next run rewrites this file from the corpus,
# which is why the note says so out loud.
distill_render_threads() {
    local out="${1:-$DISTILL_ROOT/Open threads.md}" n
    distill_have_vault || [ -n "${1:-}" ] || return 0
    mkdir -p "$(dirname "$out")"
    n="$(distill_derive | jq -s '[.[] | select(.kind == "open_threads")] | length')"
    {
        printf -- '---\ntags:\n  - claude/open-threads\nopen: %s\n---\n\n' "${n:-0}"
        printf '# Open threads\n\n'
        printf '> [!todo] Left unfinished\n'
        printf '> Most recently seen first. An entry disappears when it stops being\n'
        printf '> mentioned — from here, going quiet is what closing it looks like.\n'
        printf '>\n'
        printf '> Ticking a box is a note to yourself: this file is rebuilt from the\n'
        printf '> corpus on every run.\n\n'
        distill_derive |
            jq -s -r '[.[] | select(.kind == "open_threads")]
                | sort_by(.last_seen) | reverse
                | if length == 0 then
                    "*Nothing outstanding.*"
                  else
                    .[] | "- [ ] **\(.text)**\n\t\(.detail)\n\t*last seen \(.last_seen) · [[\(.topic | gsub("/"; "-"))]]*\n"
                  end'
    } >"$out"
}

# distill_link_topics — make Topics/ reachable from inside the vault.
#
# The topic notes live beside MAIN.md because that is where Claude reads them, but
# Obsidian can only follow a wikilink to a note inside the vault. A symlink gives
# both: one copy on disk, links that resolve, and a graph that is not empty. It is
# kept out of the vault's git — a committed symlink is an absolute path that is
# wrong on every other machine.
distill_link_topics() {
    local folder mem name
    distill_have_vault || return 0
    folder="$(distill_cfg folder 30-Claude)"
    mem="$(distill_memory_dir)"

    # Everything Claude reads, made visible where the human reads. Obsidian is the
    # only window onto this, so a rule that governs every session must not be the
    # one thing you cannot see from here.
    for name in Topics MAIN.md Candidates.md; do
        [ -e "$mem/$name" ] || continue
        _distill_link_into_vault "$mem/$name" "$DISTILL_ROOT/$name" "$folder/$name"
    done
}

# _distill_link_into_vault TARGET LINK IGNORE-PATH — one symlink, and its entry in
# the vault's .gitignore. Never committed: a symlink in git is an absolute path
# that is wrong on every other machine, and the target is generated anyway.
_distill_link_into_vault() {
    local target="$1" link="$2" ignore_path="$3" ignore

    if [ -L "$link" ]; then
        [ "$(readlink "$link")" = "$target" ] || ln -sfn "$target" "$link"
    elif [ -e "$link" ]; then
        # A real file or directory here is the pre-split layout, or a copy someone
        # made. Never replace one silently — that would delete notes.
        distill_warn "$link is real, not a link — leaving it alone"
        return 0
    else
        ln -s "$target" "$link" 2>/dev/null || return 0
    fi

    ignore="$DISTILL_VAULT/.gitignore"
    grep -qxF "$ignore_path" "$ignore" 2>/dev/null && return 0
    printf '%s\n' "$ignore_path" >>"$ignore"
}

# distill_render_index — the folder explaining itself, in the folder.
#
# Everything about how this works is documented in the dotfiles repo, which is not
# where you are when you are reading your notes. This is the Obsidian-side entry
# point. The day list is a `base` block rather than a written-out list, so it stays
# correct without this file being rewritten — the same pattern as _meta/Home.md.
distill_render_index() {
    local out="${1:-$DISTILL_ROOT/README.md}" folder
    distill_have_vault || [ -n "${1:-}" ] || return 0
    mkdir -p "$(dirname "$out")"
    folder="$(distill_cfg folder 30-Claude)"
    {
        printf -- '---\ntags:\n  - claude\n---\n\n'
        printf '# Claude, distilled\n\n'
        printf '> [!info] What this is\n'
        printf '> What past Claude Code sessions on this Mac worked out, written up each\n'
        printf '> night at 01:00. Everything here is generated — edit `Pinned.md`, not\n'
        printf '> these notes.\n\n'

        printf '## Start here\n\n'
        printf -- '| Note | What it answers |\n|---|---|\n'
        printf -- '| [[Decisions]] | What did I settle, and against what? |\n'
        printf -- '| [[Open threads]] | What do I still owe? |\n'
        printf -- '| [[MAIN]] | What is Claude actually loading in every session? |\n'
        printf -- '| `Topics/` | Any rule, with its full reasoning, by subject. |\n'
        printf -- '| [[Candidates]] | Seen once — waiting for a second sighting. |\n'
        printf -- '| [[Runs]] | Did the job run, and did it work? |\n\n'

        printf '## Days\n\n'
        printf '```base\nviews:\n  - type: table\n    name: Daily reports\n'
        printf '    filters:\n      and:\n'
        printf "        - 'file.inFolder(\"%s/Daily\")'\n" "$folder"
        printf '    order:\n      - file.name\n      - items\n      - sessions\n'
        printf '    sort:\n      - property: file.name\n        direction: DESC\n'
        printf '    limit: 30\n```\n\n'

        printf '## How something gets here\n\n'
        printf 'Each night the job reads the sessions written since it last looked and asks\n'
        printf 'a model what is worth keeping. Those items land in `Daily/`.\n\n'
        printf '> [!important] The two-sighting rule\n'
        printf '> An item seen in **two separate sessions** is also written into `MAIN.md`,\n'
        printf '> which every future Claude session loads. One conversation is not enough:\n'
        printf '> that gate is what stops a single misreading becoming a rule applied\n'
        printf '> everywhere, unattended.\n>\n'
        printf '> Decisions and open threads skip it. A decision made once is still a\n'
        printf '> decision, and you are reading those yourself.\n\n'

        printf '## Fixing one\n\n'
        printf '> [!warning] Not by editing these notes\n'
        printf '> The next run rewrites them from the corpus.\n\n'
        printf -- '| Situation | What to do |\n|---|---|\n'
        printf -- '| A rule is wrong | Write the correct one in `%s`. It goes into `MAIN.md` verbatim and is never demoted or rewritten. |\n' \
            "$(distill_tilde "$(distill_pinned_file)")"
        printf -- '| Last night made a mess | `chezdistill --undo` |\n'
        printf -- '| You changed something and want to see it | `chezdistill --render` — free, no model calls |\n'
        printf -- '| An entry should be gone entirely | Delete its sightings from `~/.local/state/chezdistill/extracts/` |\n'
        printf -- '| It keeps missing something you wanted | Edit the rubric, not the code — see below |\n\n'

        printf '## Changing what gets captured\n\n'
        printf 'What counts as worth keeping, and how these notes read, are three Markdown\n'
        printf 'prompts rather than anything in the code:\n\n'
        printf -- '| Prompt | Decides |\n|---|---|\n'
        printf -- '| `skills/distill/SKILL.md` | what gets captured at all |\n'
        printf -- '| `skills/distill-daily/SKILL.md` | how the daily summary reads |\n'
        printf -- '| `skills/distill-weekly/SKILL.md` | how the weekly review reads |\n\n'
        printf 'They live in `~/Developer/personal/dotfiles/src/dot_config/claude/skills/`,\n'
        printf 'deploy to `~/.config/claude/skills/`, and each doubles as a `/distill`\n'
        printf 'command you can run on a live conversation.\n\n'
        printf 'Full guide: `~/Developer/personal/dotfiles/docs/distill.md`.\n'
    } >"$out"
}

# ─── Daily and weekly reports ─────────────────────────────────────────────────
#
# The item sections are RENDERED from the extract corpus, not spliced into an
# existing file. Since the items are a pure function of the extracts, recomputing
# them is idempotent, and "keep the existing lines verbatim" stops being an
# instruction the model could disobey. Only the narrative is model-written, and it
# is stored beside the extracts so a re-render preserves it.

distill_narrative_file() {
    printf '%s/narratives/%s.md\n' "$(distill_state_dir)" "$1"
}

distill_extract_file() {
    printf '%s/%s.json\n' "$(distill_extracts_dir)" "$1"
}

# distill_sources_fingerprint DATE — a content hash of the day's extract. This is
# the cheap check that keeps a re-run of an already-distilled day free: `--since
# 7d` over a week that has already been read makes no model call at all.
distill_sources_fingerprint() {
    local f
    f="$(distill_extract_file "$1")"
    [ -f "$f" ] || return 0
    printf '%s\n' "$(distill_sha <"$f")"
}

# distill_sources_match DATE — 0 when the report already reflects the extract.
distill_sources_match() {
    local date="$1" recorded current
    recorded="$(distill_narrative_file "$date")"
    recorded="${recorded%.md}.sources"
    [ -f "$recorded" ] || return 1
    current="$(distill_sources_fingerprint "$date")"
    [ "$(cat "$recorded")" = "$current" ]
}

# distill_render_daily DATE — deterministic given the extracts and the narrative.
#
# The front matter is not decoration: `items` and `sessions` are what the `base`
# table on the index sorts and shows, so they have to be properties rather than
# prose. Prev/next links exist because a chronological folder with no navigation
# is one you only ever enter from the top.
distill_render_daily() {
    local date="$1" out narrative kind items diff n_items n_sess prev next
    distill_have_vault || return 0
    out="$DISTILL_ROOT/Daily/$date.md"
    narrative="$(distill_narrative_file "$date")"
    diff="$(distill_state_dir)/main-diff-$date.txt"
    items="$(mktemp)"
    mkdir -p "$(dirname "$out")"

    n_items="$(distill_date_items "$date" | jq -s 'length')"
    n_sess="$(distill_date_items "$date" | jq -s '[.[].session] | unique | length')"
    prev="$(distill_adjacent_date "$date" prev)"
    next="$(distill_adjacent_date "$date" next)"

    {
        printf -- '---\ndate: %s\ntags:\n  - claude/daily\nitems: %s\nsessions: %s\n---\n\n' \
            "$date" "${n_items:-0}" "${n_sess:-0}"
        printf '# %s\n\n' "$date"

        # A nav line only when there is somewhere to go, so the first and last
        # notes do not carry a dead link.
        if [ -n "$prev" ] || [ -n "$next" ]; then
            [ -n "$prev" ] && printf '[[%s|← %s]]' "$prev" "$prev"
            [ -n "$prev" ] && [ -n "$next" ] && printf ' · '
            [ -n "$next" ] && printf '[[%s|%s →]]' "$next" "$next"
            printf ' · [[README|index]]\n\n'
        else
            printf '[[README|index]]\n\n'
        fi

        if [ -s "$diff" ]; then
            printf '> [!important] MAIN.md changed\n'
            printf '> What every future session now loads, or no longer does.\n>\n'
            sed 's/^/> - `/; s/$/`/' "$diff"
            printf '\n'
        fi

        if [ -s "$narrative" ]; then
            printf '## Summary\n\n'
            # The narrative now arrives as markdown — its own callout and its own
            # sub-headings. Narratives written before that change are a bare
            # paragraph, and are still cached, so wrap those to match rather than
            # leaving old notes looking different forever.
            if head -1 "$narrative" | grep -q '^>'; then
                cat "$narrative"
            else
                sed 's/^/> /' "$narrative" | sed '1s/^> /> [!abstract] /'
            fi
            printf '\n'
        fi

        for kind in decisions open_threads gotchas learnings preferences \
            questions_answered; do
            distill_date_items "$date" |
                jq -r --arg k "$kind" \
                    'select(.kind == $k)
                     | "- \(.text)  ·  [[\((.topic // "General") | gsub("/"; "-"))]]"' |
                sort -u >"$items"
            [ -s "$items" ] || continue
            printf '\n## %s\n\n' "$(distill_kind_title "$kind")"
            cat "$items"
        done

        printf '\n---\n\n'
        printf '*%s item(s) from %s session(s) · fingerprint `%s`*\n' \
            "${n_items:-0}" "${n_sess:-0}" "$(distill_sources_fingerprint "$date")"
    } >"$out"
    rm -f "$items"
}

# distill_adjacent_date DATE prev|next — the neighbouring day that actually has a
# report, so the link never points at a note that was never written.
distill_adjacent_date() {
    local date="$1" dir="$2"
    /usr/bin/find "$(distill_extracts_dir)" -name '*.json' 2>/dev/null |
        while IFS= read -r f; do basename "$f" .json; done | sort |
        if [ "$dir" = "prev" ]; then
            awk -v d="$date" '$0 < d {last=$0} END {print last}'
        else
            awk -v d="$date" '$0 > d {print; exit}'
        fi
}

distill_kind_title() {
    case "$1" in
        decisions) printf 'Decisions' ;;
        preferences) printf 'Preferences' ;;
        learnings) printf 'Learnings' ;;
        questions_answered) printf 'Questions answered' ;;
        open_threads) printf 'Left open' ;;
        gotchas) printf 'Gotchas' ;;
    esac
}

# distill_date_items DATE — the day's items, flattened.
distill_date_items() {
    local f
    f="$(distill_extract_file "$1")"
    [ -f "$f" ] || return 0
    jq -c '.items[]?' "$f" 2>/dev/null
}

# ─── Git ──────────────────────────────────────────────────────────────────────
#
# Two repos, and the difference between them is the whole point. The vault has a
# remote and carries the reports. Memory and state share a local repo with NO
# remote: it exists so `--undo` still means something now that MAIN.md lives
# outside the vault. Its remote is optional: add one and the corpus survives the
# machine.
#
# Being offline is not an error for the vault either: the work is done, committed
# locally, and pushed by whichever run next has a network. Neither path ever
# touches the repo this script ships in.

# Never let the network block a headless job. Without these an unreachable remote
# makes git sit on an SSH or credential prompt forever, and a launchd job has no
# terminal to answer it — the run hangs until the machine is rebooted.
distill_git_env() {
    export GIT_TERMINAL_PROMPT=0
    export GIT_ASKPASS=/usr/bin/true
    export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
}

distill_git_pull() {
    [ "${DRY_RUN:-0}" = "1" ] && return 0
    distill_have_vault || return 0
    distill_git_env
    git -C "$DISTILL_VAULT" pull --rebase --autostash >/dev/null 2>&1 ||
        distill_warn "could not pull the vault (offline?) — continuing locally"
}

# distill_state_repo_pushurl — push this repo over the URL it was cloned from.
#
# A global `url.git@github.com:.pushinsteadof https://github.com/` rewrites every
# HTTPS push to SSH, and this machine's SSH key lives behind 1Password. At 01:00
# the Mac is asleep or locked, so the agent is locked, so the push fails and the
# corpus quietly stops leaving the machine until someone runs the job by hand —
# which is the opposite of what a backup is for.
#
# Pinning the push URL to the fetch URL opts this one repo out of that rewrite.
# It is set only when the remote is already HTTPS and no push URL was configured,
# so an SSH remote is left exactly as the user set it up.
distill_state_repo_pushurl() {
    local repo fetch
    repo="$(distill_state_dir)"
    fetch="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 0
    case "$fetch" in https://*) ;; *) return 0 ;; esac
    [ -z "$(git -C "$repo" config --get remote.origin.pushurl 2>/dev/null)" ] || return 0
    git -C "$repo" config remote.origin.pushurl "$fetch" >/dev/null 2>&1 || true
}

# distill_commit_local MESSAGE — commit the state dir. No remote, so no push, no
# pull, and no way for this to fail on a network.
#
# Only state is tracked, not memory. MAIN.md, Topics/ and Candidates.md are a
# pure function of the extract corpus, so reverting the inputs and
# re-rendering puts the memory tier back exactly — which is what `--undo` does.
# Versioning derived output alongside its input would just be two copies of the
# same decision, free to disagree.
distill_commit_local() {
    local repo="" msg="$1"
    repo="$(distill_state_dir)"
    [ "${DRY_RUN:-0}" = "1" ] && {
        dim "dry-run \$ git -C $repo commit -m '$msg'"
        return 0
    }
    [ -d "$repo" ] || return 0

    distill_state_repo_init || return 0
    git -C "$repo" add -A >/dev/null 2>&1 || true
    if ! git -C "$repo" diff --cached --quiet 2>/dev/null; then
        git -C "$repo" commit -q -m "$msg" >/dev/null 2>&1 || {
            distill_warn "could not commit the state repo"
            return 0
        }
    fi

    # Only if one was configured. Offline is not an error here either: the commit
    # is already made, and the next run carries it.
    [ -n "$(git -C "$repo" remote 2>/dev/null)" ] || return 0
    distill_git_env
    git -C "$repo" push -q >/dev/null 2>&1 || {
        git -C "$repo" pull --rebase --autostash >/dev/null 2>&1 || true
        git -C "$repo" push -q >/dev/null 2>&1 ||
            info "state push deferred — the next run will carry it"
    }
    return 0
}

# distill_state_repo_init — created on first use. A remote is optional: add one
# by hand (`git -C <state> remote add origin …`) and every run pushes to it, so a
# replacement Mac clones the corpus instead of starting from an empty memory.
#
# `logs/` is excluded because launchd's stdout is noise and the one thing here
# that grows without bound. `cursor.json` is excluded because it answers "how far
# has THIS machine read", which is meaningless on any other one.
#
# Identity and signing are pinned locally rather than inherited. A global
# `commit.gpgsign = true` backed by 1Password's op-ssh-sign raises a GUI approval
# prompt, and a launchd job at 01:00 has nobody to approve it — the commit would
# hang or fail every night. Nothing here is published or attributed to anyone, so
# there is nothing for a signature to attest to.
distill_state_repo_init() {
    local repo pat
    repo="$(distill_state_dir)"
    mkdir -p "$repo" || return 1
    if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$repo" init -q >/dev/null 2>&1 || {
            distill_warn "could not init the state repo at $repo — --undo will not work"
            return 1
        }
    fi
    git -C "$repo" config commit.gpgsign false >/dev/null 2>&1 || true
    git -C "$repo" config user.name chezdistill >/dev/null 2>&1 || true
    git -C "$repo" config user.email chezdistill@localhost >/dev/null 2>&1 || true
    distill_state_repo_pushurl
    # Ensure each rule, rather than only writing the file when absent: a repo
    # initialised by an older version keeps its old .gitignore forever, and a
    # rule added later would never reach it. Untrack too — .gitignore has no
    # effect on a path that is already in the index.
    for pat in 'logs/' 'cursor.json' '*.tmp' 'main-diff-*.txt'; do
        grep -qxF "$pat" "$repo/.gitignore" 2>/dev/null && continue
        printf '%s\n' "$pat" >>"$repo/.gitignore"
    done
    git -C "$repo" ls-files -z --cached -i --exclude-standard 2>/dev/null |
        xargs -0 -r git -C "$repo" rm -q --cached -- 2>/dev/null || true
    return 0
}

# distill_git_push MESSAGE — commit and push, rebasing once on rejection.
distill_git_push() {
    local msg="$1" folder
    folder="$(distill_cfg folder 30-Claude)"
    [ "${DRY_RUN:-0}" = "1" ] && {
        dim "dry-run \$ git commit -m '$msg' && git push"
        return 0
    }
    distill_have_vault || return 0

    distill_git_env
    git -C "$DISTILL_VAULT" add -- "$folder" >/dev/null 2>&1 || true
    git -C "$DISTILL_VAULT" diff --cached --quiet 2>/dev/null && return 0
    git -C "$DISTILL_VAULT" commit -q -m "$msg" >/dev/null 2>&1 || {
        warn "vault commit failed"
        return 1
    }

    if ! git -C "$DISTILL_VAULT" push -q >/dev/null 2>&1; then
        git -C "$DISTILL_VAULT" pull --rebase --autostash >/dev/null 2>&1 || true
        git -C "$DISTILL_VAULT" push -q >/dev/null 2>&1 ||
            info "push deferred — the next run will carry it"
    fi
}

# ─── Skills ───────────────────────────────────────────────────────────────────
#
# Skill discovery is exactly one level deep — verified on this install:
# ~/.config/claude/skills/<name>/SKILL.md is found, skills/generated/<name>/ is
# not. So generated skills are mirrored FLAT under a `distilled-` prefix, which
# is also the only glob this mirror is allowed to touch: `skills/distill/` and
# `skills/distill-weekly/` are chezmoi-managed and sit in the same directory.

distill_skills_target() {
    printf '%s/skills\n' "${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}"
}

distill_sync_skills() {
    local src dest name
    src="$(distill_state_dir)/skills"
    dest="$(distill_skills_target)"
    [ -d "$src" ] || return 0
    mkdir -p "$dest"

    for d in "$dest"/distilled-*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        [ -d "$src/${name#distilled-}" ] || rm -rf "$d"
    done

    for d in "$src"/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        mkdir -p "$dest/distilled-$name"
        cp -f "$d/SKILL.md" "$dest/distilled-$name/SKILL.md" 2>/dev/null || true
    done
}

# ─── Status ───────────────────────────────────────────────────────────────────

distill_status() {
    local main cap spent ceiling n last line f
    s_section "chezdistill"

    if ! distill_preflight; then
        s_fail "paths    unusable"
        return 0
    fi

    s_pass "memory   $(distill_memory_dir)"
    s_pass "state    $(distill_state_dir)"
    if distill_have_vault; then
        s_pass "vault    $DISTILL_ROOT"
    else
        s_warn "vault    not available — reports would be skipped, memory still renders"
    fi

    main="$(distill_memory_dir)/MAIN.md"
    cap="$(distill_cfg mainCapBytes 6144)"
    if [ -f "$main" ]; then
        n="$(wc -c <"$main" | tr -d ' ')"
        if [ "$n" -le "$cap" ]; then
            s_pass "MAIN.md  ${n}B of ${cap}B"
        else
            s_warn "MAIN.md  ${n}B, over the ${cap}B cap"
        fi
    else
        s_note "MAIN.md  not rendered yet"
    fi

    n="$(distill_derive | jq -s 'length' 2>/dev/null || echo 0)"
    line="$(distill_derive | jq -s -r 'if length == 0 then "" else
        "\([.[].hits] | add) sighting(s) of \(length) entr\(if length == 1 then "y" else "ies" end), oldest \([.[].first_seen] | min)"
        end' 2>/dev/null || true)"
    s_note "corpus   ${line:-nothing extracted yet}"

    n="$(distill_eligible | jq -s '[.[] | select(.eligible | not)] | length' 2>/dev/null || echo 0)"
    if [ "${n:-0}" -gt 0 ]; then
        s_note "waiting  ${n} entries below the gate or stale — see Candidates.md"
    fi

    if git -C "$(distill_state_dir)" rev-parse --git-dir >/dev/null 2>&1; then
        n="$(git -C "$(distill_state_dir)" rev-list --count HEAD 2>/dev/null || echo 0)"
        if [ -n "$(git -C "$(distill_state_dir)" remote 2>/dev/null)" ]; then
            s_pass "backup   $n commit(s), pushed to $(git -C "$(distill_state_dir)" remote get-url origin 2>/dev/null)"
        else
            s_warn "backup   $n commit(s), no remote — this Mac is the only copy"
        fi
    else
        s_note "backup   no state repo yet — the first run creates it"
    fi

    # Rounded for display the same way Runs.md rounds it. The raw sum is a float
    # accumulated from per-call costs, so it reads as $2.7951789000000002.
    spent="$(distill_spend_7d | jq -r '. * 100 | round / 100')"
    ceiling="$(distill_cfg maxSpendUsd7d 15.0)"
    s_note "spend    \$$spent of \$$ceiling over 7 days"

    last="$(distill_last_run)"
    if [ -z "$last" ]; then
        s_note "last run no run recorded yet — see Runs.md once one has"
    else
        line="$(printf '%s' "$last" | jq -r \
            '"\(.end[0:16] | sub("T"; " ")) UTC · \(.mode) · \(.status)"
             + " · \(.sessions.kept)/\(.sessions.seen) session(s) · $\(.cost * 100 | round / 100)"')"
        case "$(printf '%s' "$last" | jq -r '.status')" in
            ok) s_pass "last run $line" ;;
            *) s_fail "last run $line" ;;
        esac
    fi

    f="$(distill_cursor_file)"
    [ -f "$f" ] && s_note "cursor   read up to $(jq -r '.cursor // "?"' "$f")"
    return 0
}

# ─── Schemas ──────────────────────────────────────────────────────────────────

# One call per session, not two. Measured on real transcripts, a separate Haiku
# triage pass cost $0.05/session while the map cost $0.23 — but each call also
# re-pays ~19k tokens of cached harness context, so splitting them was buying a
# cheap gate with an expensive round trip. `items: []` is the triage verdict.
distill_schema_map() {
    cat <<'JSON'
{"type":"object","additionalProperties":false,
 "required":["items"],
 "properties":{"items":{"type":"array","items":{
   "type":"object","additionalProperties":false,
   "required":["text","detail","kind","topic","evidence","confidence"],
   "properties":{
     "text":{"type":"string","maxLength":200},
     "detail":{"type":"string"},
     "kind":{"type":"string","enum":["decisions","preferences","learnings",
             "questions_answered","open_threads","gotchas"]},
     "topic":{"type":"string"},
     "evidence":{"type":"string"},
     "confidence":{"type":"string","enum":["low","medium","high"]}}}}}}
JSON
}

# Sections rather than one `summary` string. The old schema asked for a blob and
# got one: a 400-word paragraph nobody re-reads. maxLength on the lede is the same
# trick as the 200-char rule text — a length asked for in a prompt is ignored, a
# length in the schema is not.
distill_schema_narrative() {
    cat <<'JSON'
{"type":"object","additionalProperties":false,
 "required":["lede","sections"],
 "properties":{
   "lede":{"type":"string","maxLength":300},
   "sections":{"type":"array","minItems":1,"maxItems":4,"items":{
     "type":"object","additionalProperties":false,
     "required":["heading","body"],
     "properties":{
       "heading":{"type":"string","maxLength":60},
       "body":{"type":"string"}}}}}}
JSON
}

# ─── Cursor ───────────────────────────────────────────────────────────────────

distill_cursor_file() {
    printf '%s/cursor.json\n' "$(distill_state_dir)"
}

# distill_cursor_read — where the job last read to. The cursor, rather than
# "yesterday", is what makes a laptop that slept through 01:00 lose nothing.
distill_cursor_read() {
    local f
    f="$(distill_cursor_file)"
    if [ -n "${DISTILL_SINCE:-}" ]; then
        printf '%s\n' "$DISTILL_SINCE"
    elif [ -f "$f" ]; then
        jq -r '.cursor // empty' "$f" 2>/dev/null || distill_iso_ago 1
    else
        distill_iso_ago 1
    fi
}

distill_cursor_write() {
    local f
    f="$(distill_cursor_file)"
    mkdir -p "$(dirname "$f")"
    jq -n --arg c "$1" '{cursor:$c}' >"$f"
}

# ─── Nightly ──────────────────────────────────────────────────────────────────

# distill_run_daily — the nightly job, wrapped in a run record. The wrapper is
# what makes a failure visible: whatever the body does, distill_run_end still
# writes the record and is the one place that commits.
distill_run_daily() {
    local rc
    distill_run_begin daily
    _distill_daily_body
    rc=$?
    distill_run_end "$rc" || rc=1
    return "$rc"
}

_distill_daily_body() {
    local since now tmp sysfile schema filtered turns cwd out
    local sess name title mapped date n_items persisted=1

    distill_spend_ok || return 1
    distill_git_pull

    since="$(distill_cursor_read)"
    _DISTILL_RUN_SINCE="$since"
    now="$(distill_iso_now)"
    tmp="$(mktemp -d)"

    sysfile="$tmp/rubric.md"
    distill_rubric >"$sysfile"
    schema="$tmp/map.json"
    distill_schema_map >"$schema"

    info "reading transcripts since $since"

    while IFS= read -r sess; do
        [ -n "$sess" ] || continue
        name="$(basename "$sess" .jsonl)"
        DISTILL_RUN_SEEN=$((DISTILL_RUN_SEEN + 1))
        filtered="$tmp/$name.ndjson"
        distill_filter "$sess" "$since" | distill_dedupe >"$filtered"
        if [ ! -s "$filtered" ]; then
            distill_run_session "$name" 0 "nothing new since the cursor" 0
            continue
        fi

        turns="$(distill_turns <"$filtered")"
        cwd="$(jq -r 'select(.c != null) | .c' <"$filtered" | head -1)"
        title="$(distill_session_title "$sess")"
        date="$(jq -r '.t[0:10]' <"$filtered" | head -1)"

        if [ "${turns:-0}" -lt "$(distill_cfg minTurns 3)" ]; then
            dim "skip $name — only ${turns} typed turn(s)"
            distill_run_session "$name" "${turns:-0}" "too short, no model call" 0
            continue
        fi

        mapped="$(distill_claude "$(distill_cfg mapModel sonnet)" "$sysfile" "$schema" \
            "Session title: ${title:-untitled}. Extract durable items, or none." \
            <"$filtered")" || {
            distill_run_session "$name" "$turns" "model call failed" 0
            continue
        }

        n_items="$(printf '%s' "$mapped" | jq -r '.items | length')"
        if [ "${n_items:-0}" = "0" ]; then
            dim "skip $name — nothing durable in it"
            distill_run_session "$name" "$turns" "nothing durable in it" 0
            continue
        fi

        printf '%s\n' "$mapped" |
            jq -c --arg s "$name" \
                --arg c "$cwd" --arg tool "${DISTILL_TOOL:-claude-code}" \
                '.items[] | . + {session:$s, cwd:$c, tool:$tool}' \
                >>"$tmp/items-$date.ndjson"
        DISTILL_RUN_KEPT=$((DISTILL_RUN_KEPT + 1))
        DISTILL_RUN_ITEMS=$((DISTILL_RUN_ITEMS + n_items))
        distill_run_session "$name" "$turns" "kept" "$n_items"
    done < <(distill_session_files "$since")

    ok "$DISTILL_RUN_KEPT of $DISTILL_RUN_SEEN session(s) yielded items"

    distill_persist_extracts "$tmp" || persisted=0

    distill_finish_dates "$DISTILL_RUN_DATES" "$tmp"
    distill_prune_extracts
    if [ "$persisted" -eq 1 ]; then
        distill_cursor_write "$now"
    else
        distill_warn "cursor held at $since — the next run re-reads this window"
    fi
    rm -rf "$tmp"
    [ "$persisted" -eq 1 ]
}

# distill_persist_extracts TMPDIR — write this run's items into the corpus, one
# file per date, merged with whatever that date already holds. A backfill and a
# nightly run can both land on the same day, and `unique` keeps a session that was
# read twice from counting twice.
#
# Appends each date it wrote to DISTILL_RUN_DATES. Returns non-zero if any write
# failed, which is the one failure in this job that loses money: the model calls
# are already billed by the time this runs, and no re-run recovers them. The
# caller holds the cursor back on non-zero so the next run reads the window again.
distill_persist_extracts() {
    local tmp="$1" f date out rc=0
    for f in "$tmp"/items-*.ndjson; do
        [ -f "$f" ] || continue
        date="$(basename "$f" .ndjson)"
        date="${date#items-}"
        out="$(distill_extract_file "$date")"
        mkdir -p "$(dirname "$out")" 2>/dev/null

        if [ -f "$out" ]; then
            if jq -s '{items: (.[0].items + .[1] | unique)}' \
                "$out" <(jq -s '.' "$f") >"$out.tmp" 2>/dev/null &&
                mv "$out.tmp" "$out" 2>/dev/null; then
                :
            else
                rm -f "$out.tmp"
                rc=1
            fi
        else
            jq -s '{items: .}' "$f" >"$out" 2>/dev/null || rc=1
        fi

        if [ "$rc" -ne 0 ]; then
            distill_fail "could not write $out — extracted items not saved"
            return 1
        fi
        DISTILL_RUN_DATES="$DISTILL_RUN_DATES $date"
    done
    return 0
}

# distill_finish_dates DATES TMPDIR — narrate and render. Publishing (gitleaks,
# skills, commit) belongs to distill_run_end, so a run that never gets this far
# still leaves its record in the vault.
distill_finish_dates() {
    local dates="$1" tmp="$2" date before
    local main="$(distill_memory_dir)/MAIN.md"

    before="$tmp/main-before.md"
    cp -f "$main" "$before" 2>/dev/null || : >"$before"
    mkdir -p "$(distill_state_dir)/narratives"

    for date in $dates; do
        if distill_sources_match "$date"; then
            dim "$date is already reflected in its report — nothing to do"
            continue
        fi
        distill_narrate "$date" "$tmp"
    done

    distill_render_all

    for date in $dates; do
        distill_main_diff "$before" "$main" \
            >"$(distill_state_dir)/main-diff-$date.txt"
        distill_render_daily "$date"
        distill_sources_fingerprint "$date" \
            >"$(distill_state_dir)/narratives/$date.sources"
    done
}

# distill_narrate DATE TMPDIR — the one model call that writes prose.
# distill_narrate DATE TMPDIR — the one model call that writes prose.
#
# Stores rendered markdown, not the JSON: `--render` must be able to rebuild the
# note without paying for the call again, and the structure has no other reader.
distill_narrate() {
    local date="$1" tmp="$2" out sys
    out="$(distill_narrative_file "$date")"
    mkdir -p "$(dirname "$out")"
    sys="$tmp/rubric-daily.md"
    distill_rubric distill-daily >"$sys"
    distill_date_items "$date" |
        jq -s -r 'map("- [\(.kind)] \(.text)\n  \(.detail // "")") | join("\n")' |
        distill_claude "$(distill_cfg narrateModel opus)" "$sys" \
            <(distill_schema_narrative) \
            "Write the daily summary for $date from these items." |
        jq -r 'if .lede then
                 "> [!abstract] \(.lede)\n",
                 (.sections[]? | "### \(.heading)\n\n\(.body)\n")
               else empty end' >"$out"
}

# distill_guard_secrets — the sweep follows the content, not the directory. The
# extracts moved off the vault's remote but still quote the conversation they came
# from, and MAIN.md is loaded into every session, so all three are swept and any
# hit blocks every commit this run would have made.
distill_guard_secrets() {
    local d
    command -v gitleaks >/dev/null 2>&1 || {
        warn "gitleaks not installed — skipping the secret sweep"
        return 0
    }
    for d in "$(distill_state_dir)" "$(distill_memory_dir)" "${DISTILL_ROOT:-}"; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        if ! gitleaks dir "$d" --redact --no-banner >/dev/null 2>&1; then
            fail "gitleaks found something in $d — not committing"
            return 1
        fi
    done
    return 0
}

# ─── Weekly ───────────────────────────────────────────────────────────────────

# distill_run_weekly — same shape as the nightly job: the body does the work,
# the wrapper records the run and is the only thing that commits.
distill_run_weekly() {
    local rc
    distill_run_begin weekly
    _distill_weekly_body
    rc=$?
    distill_run_end "$rc" || rc=1
    return "$rc"
}

_distill_weekly_body() {
    local week out tmp
    distill_spend_ok || return 1
    distill_git_pull

    week="$(date -u +%G-W%V)"
    DISTILL_RUN_WEEK="$week"
    tmp="$(mktemp -d)"
    distill_rubric distill-weekly >"$tmp/rubric.md"

    distill_render_all

    if ! distill_have_vault; then
        info "vault not available — memory re-rendered, no weekly note written"
        rm -rf "$tmp"
        return 0
    fi
    out="$DISTILL_ROOT/Weekly/$week.md"
    mkdir -p "$(dirname "$out")"

    {
        printf -- '---\nweek: %s\n---\n\n# %s\n\n' "$week" "$week"
        printf '## Summary\n\n'
        distill_derive |
            jq -s -r 'map("- [\(.kind)] \(.text)") | join("\n")' |
            distill_claude "$(distill_cfg narrateModel opus)" "$tmp/rubric.md" \
                <(distill_schema_narrative) \
                "Write the weekly review for $week from these entries." |
            jq -r 'if .lede then
                     "> [!abstract] \(.lede)\n",
                     (.sections[]? | "### \(.heading)\n\n\(.body)\n")
                   else empty end'
        printf '\n## Not in MAIN.md\n\n'
        printf 'Below the promotion gate or gone stale. The full list is in\n'
        printf '`%s/Candidates.md`.\n\n' "$(distill_memory_dir)"
        distill_eligible |
            jq -r 'select(.eligible | not)
                   | "- \(.text)  ·  \(.hits) hit(s), last seen \(.last_seen)"' |
            sort
    } >"$out"

    rm -rf "$tmp"
}

# ─── Rubric ───────────────────────────────────────────────────────────────────
#
# The rubric REPLACES the default system prompt. The Skill tool is unavailable
# under `--tools ""`, so the SKILL.md is read as a file here; each still doubles
# as a manually invocable `/distill` in an interactive session.
#
# One per task, because they are different jobs. Extraction wants compression and
# is told to answer with the schema and nothing else; a summary wants readable
# prose for someone with no memory of the day. Running the narrative calls under
# the extraction rubric — which is what this did — is why they came out as walls.

# distill_rubric [SKILL] — the body of a SKILL.md, front matter stripped.
distill_rubric() {
    local name="${1:-distill}" deployed repo
    deployed="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}/skills/$name/SKILL.md"
    repo="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}/src/dot_config/claude/skills/$name/SKILL.md"
    if [ -r "$deployed" ]; then
        sed '1{/^---$/,/^---$/d;}' "$deployed"
    elif [ -r "$repo" ]; then
        sed '1{/^---$/,/^---$/d;}' "$repo"
    else
        printf 'Extract durable lessons from Claude Code sessions. Answer only with the schema.\n'
    fi
}
