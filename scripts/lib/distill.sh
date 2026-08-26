#!/usr/bin/env bash
# distill.sh — the chezdistill engine: harvest Claude Code transcripts and render
# the memory tier Claude loads.
#
# Two destinations, because the two have nothing in common:
#   DISTILL_MEMORY  ~/.config/claude/memory — MAIN.md, Topics/, Candidates.md.
#                   Read by Claude, and by nothing else.
#   DISTILL_STATE   ~/.local/state/chezdistill — the extract corpus, Pinned.md,
#                   cursor, spend, run log. The extracts ARE the memory: every
#                   rule, hit count and date is derived from them on each render.
#
# Design principle: the model extracts, bash decides and writes. Every judgement —
# hit counts, what earns a place in MAIN, what gets demoted — is computed here
# from the extract corpus, so a re-run of a day already distilled is a no-op. No
# model invocation in this file has write access.
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
# `[ -w ]` is not enough on macOS. Under TCC the POSIX bits on a protected
# directory say "writable" and the write syscall is still refused with EPERM,
# because a launchd agent has no access unless it has been granted explicitly.
# That gap is how a nightly run can spend weeks reporting success while every
# single write fails. Only an actual write tells the truth.
distill_can_write() {
    local dir="$1" probe
    [ -d "$dir" ] || return 1
    probe="$dir/.chezdistill-write-probe.$$"
    : >"$probe" 2>/dev/null || return 1
    rm -f "$probe" 2>/dev/null
    return 0
}

# distill_preflight — every precondition, checked before any processing.
# Exports DISTILL_MEMORY and DISTILL_STATE.
#
# Both are ordinary local directories the job owns outright, so they are simply
# created; there is no mount here that could be wrong, and nothing outside $HOME
# to be refused by macOS privacy protection.
# 0 = go · 1 = broken/unwritable (a real failure)
distill_preflight() {
    local d

    if ! command -v jq >/dev/null 2>&1; then
        fail "jq is required but not on PATH"
        return 1
    fi

    DISTILL_MEMORY="$(distill_expand \
        "$(distill_cfg memoryPath "$HOME/.config/claude/memory")")"
    DISTILL_STATE="$(distill_expand \
        "$(distill_cfg statePath "$HOME/.local/state/chezdistill")")"
    export DISTILL_MEMORY DISTILL_STATE

    # If these cannot be written there is nothing worth continuing for.
    mkdir -p "$DISTILL_MEMORY" "$DISTILL_STATE" 2>/dev/null || true
    for d in "$DISTILL_MEMORY" "$DISTILL_STATE"; do
        distill_can_write "$d" && continue
        fail "cannot write to $d"
        return 1
    done

    return 0
}

# distill_state_dir — every file no human reads.
# distill_memory_dir — what Claude loads.
#
# Both read the exported value when preflight has run and fall back to the
# configured path when it has not, so a caller that runs before preflight still
# lands where the config says rather than on the built-in default.
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

# distill_seed_pinned — create it empty, once, and never touch it again.
#
# Every generated note tells you to fix a wrong rule by editing this file. Until
# something creates it, that instruction points at nothing, and the format it
# wants — plain bullets, copied verbatim — is not guessable from an absent file.
# The seed is one comment line because the whole file is pasted into MAIN.md and
# competes with the distilled rules for the same 6 KB.
distill_seed_pinned() {
    local f
    f="$(distill_pinned_file)"
    [ -e "$f" ] && return 0
    mkdir -p "$(dirname "$f")" || return 0
    printf '<!-- Hand-written. Copied into MAIN.md verbatim, never demoted. One `- ` rule per line. -->\n' \
        >"$f"
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
# One record per run, appended to runs.jsonl and read back by `--status`. The
# point is the runs nobody watches: a nightly job that skipped every session at
# 01:00 otherwise leaves its only trace in a launchd log, and "nothing ran" and
# "nothing was worth keeping" have to stay distinguishable.
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

# distill_run_begin — open the record for this run.
distill_run_begin() {
    _DISTILL_RUN_START="$(distill_iso_now)"
    _DISTILL_RUN_EPOCH="$(date -u +%s)"
    _DISTILL_RUN_SINCE=""
    _DISTILL_EVENTS="$(mktemp)"
    _DISTILL_SESSIONS="$(mktemp)"
    DISTILL_RUN_SEEN=0
    DISTILL_RUN_KEPT=0
    DISTILL_RUN_ITEMS=0
    DISTILL_RUN_DATES=""
}

# distill_event LEVEL TEXT — remember a line for the record. A no-op outside a
# run, so --status and --render can call the same helpers.
distill_event() {
    [ -f "${_DISTILL_EVENTS:-}" ] || return 0
    printf '%s\t%s\n' "$1" "$2" >>"$_DISTILL_EVENTS"
}

# distill_warn / distill_fail — say it on the console AND keep it in the run
# record. Nobody reads the launchd log of the Mac that was asleep.
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
        --arg trigger "${DISTILL_TRIGGER:-manual}" \
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
        '{t:$t, end:$end, dur:$dur, trigger:$trigger,
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

# distill_run_last_detail — the newest run, per session, as plain lines. What
# makes a quiet run legible: "7 seen, 0 kept" is alarming until you can see that
# six were under minTurns and one had nothing durable in it.
distill_run_last_detail() {
    distill_run_all | jq -s -r '
        (sort_by(.t) | last) as $r
        | if $r == null then empty
          else ($r.sessions.detail // [])[]
               | "\(.session[0:8])  \(.turns) turn(s) · \(.verdict)"
                 + (if .items > 0 then " · \(.items) item(s)" else "" end)
          end' 2>/dev/null
}

# distill_run_message STATUS — the commit subject for this run.
distill_run_message() {
    local dates="${DISTILL_RUN_DATES:-}"
    if [ "$1" != "ok" ]; then
        printf 'chore(distill): failed run\n'
    elif [ -n "${dates// /}" ]; then
        printf 'chore(distill): extracts for%s\n' "$dates"
    else
        printf 'chore(distill): run log\n'
    fi
}

# distill_run_end RC — close the record and publish. This is the ONLY place
# anything is committed: a run that failed half way still has to leave its record
# behind, and putting the record in the same commit as the extracts is what keeps
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
    fi
    rm -f "${_DISTILL_EVENTS:-}" "${_DISTILL_SESSIONS:-}"
    _DISTILL_EVENTS=""
    _DISTILL_SESSIONS=""

    distill_guard_secrets || return 1
    distill_sync_skills
    distill_commit_local "$msg"
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

# distill_render_all — every generated file. One entry point so a new one cannot
# be added to the nightly path and forgotten in --render.
distill_render_all() {
    distill_render_main
    distill_render_inbox
    distill_render_topics
}

# distill_extract_file DATE — one day of the corpus.
distill_extract_file() {
    printf '%s/%s.json\n' "$(distill_extracts_dir)" "$1"
}

# ─── Git ──────────────────────────────────────────────────────────────────────
#
# One repo: the state dir. It exists so `--undo` still means something, since the
# memory tier is derived and can always be re-rendered from the corpus. Its
# remote is optional — add one and the corpus survives the machine. This path
# never touches the repo this script ships in.

# Never let the network block a headless job. Without these an unreachable remote
# makes git sit on an SSH or credential prompt forever, and a launchd job has no
# terminal to answer it — the run hangs until the machine is rebooted.
distill_git_env() {
    export GIT_TERMINAL_PROMPT=0
    export GIT_ASKPASS=/usr/bin/true
    export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
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

# distill_render_state_readme — the repo explaining itself, on GitHub.
#
# This one is not for you and not for Claude: it is for whoever opens the remote
# on a machine that has none of this set up, which in practice is you on a
# replacement Mac. A backup you cannot interpret is not a backup, and the restore
# procedure is two commands that are impossible to guess from the file names.
#
# Deterministic like every other render, so a run that changed nothing produces
# no commit.
distill_render_state_readme() {
    local out="${1:-$(distill_state_dir)/README.md}" remote
    # Read back from git rather than a config key, so the clone line in the
    # README can never name a remote this repo does not actually push to.
    remote="$(git -C "$(distill_state_dir)" remote get-url origin 2>/dev/null || true)"
    mkdir -p "$(dirname "$out")"
    {
        printf '# claude-memory\n\n'
        printf 'The corpus behind my Claude Code memory. Written by `chezdistill`, a\n'
        printf 'nightly job in [dotfiles](https://github.com/martinzachariassen/dotfiles);\n'
        printf 'nothing here is edited by hand.\n\n'

        printf 'Each night the job reads the Claude Code sessions written since it last\n'
        printf 'looked, asks a model what is worth keeping, and stores the answer. The\n'
        printf 'rules Claude actually loads (`MAIN.md`, `Topics/`) are **not** in this\n'
        printf 'repo — they are regenerated from what is, so keeping both would be two\n'
        printf 'copies of one decision, free to disagree.\n\n'

        printf '## What is in here\n\n'
        printf -- '| Path | What it is |\n|---|---|\n'
        printf -- '| `extracts/<date>.json` | One file per day: every item the model kept, with a short quote as evidence. **The source of truth** — everything else is derived from this. |\n'
        printf -- '| `runs.jsonl` | One record per run: when, how long, what it cost, what broke. |\n'
        printf -- '| `spend.jsonl` | Per-call cost, which the rolling 7-day ceiling reads back. |\n'
        printf -- '| `Pinned.md` | The hand-written rules. Copied here because they are the one thing that cannot be regenerated. |\n\n'

        printf 'Deliberately absent: `cursor.json` (how far *this* Mac has read — meaningless\n'
        printf 'on another) and `logs/` (launchd noise, and the only thing here that grows\n'
        printf 'without bound).\n\n'

        printf '## Restoring onto a new Mac\n\n'
        printf 'Set the dotfiles up first, then:\n\n'
        printf '```sh\n'
        printf 'git clone %s \\\n' "${remote:-<this repo>}"
        printf '    ~/.local/state/chezdistill\n'
        printf 'chezdistill --render\n'
        printf '```\n\n'
        printf '`--render` makes no model calls and costs nothing. It rebuilds `MAIN.md`,\n'
        printf '`Topics/` and `Candidates.md` from the extracts, so the new machine starts\n'
        printf 'with the memory the old one had rather than an empty one.\n\n'

        printf '## Why it is private\n\n'
        printf 'Each item carries a short quote from the conversation it came from, as\n'
        printf 'evidence for why it was kept. That is transcript text. Quotes are stripped\n'
        printf 'from items older than the retention window, but the recent ones are real,\n'
        printf 'so this repo stays private and every push is scanned by `gitleaks` first.\n'
    } >"$out"
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
    distill_render_state_readme
    distill_seed_pinned
    # Ensure each rule, rather than only writing the file when absent: a repo
    # initialised by an older version keeps its old .gitignore forever, and a
    # rule added later would never reach it. Untrack too — .gitignore has no
    # effect on a path that is already in the index.
    for pat in 'logs/' 'cursor.json' '*.tmp'; do
        grep -qxF "$pat" "$repo/.gitignore" 2>/dev/null && continue
        printf '%s\n' "$pat" >>"$repo/.gitignore"
    done
    git -C "$repo" ls-files -z --cached -i --exclude-standard 2>/dev/null |
        xargs -0 -r git -C "$repo" rm -q --cached -- 2>/dev/null || true
    return 0
}

# ─── Skills ───────────────────────────────────────────────────────────────────
#
# Skill discovery is exactly one level deep — verified on this install:
# ~/.config/claude/skills/<name>/SKILL.md is found, skills/generated/<name>/ is
# not. So generated skills are mirrored FLAT under a `distilled-` prefix, which
# is also the only glob this mirror is allowed to touch: `skills/distill/` is
# chezmoi-managed and sits in the same directory.

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

    # Rounded for display. The raw sum is a float accumulated from per-call
    # costs, so it reads as $2.7951789000000002.
    spent="$(distill_spend_7d | jq -r '. * 100 | round / 100')"
    ceiling="$(distill_cfg maxSpendUsd7d 15.0)"
    s_note "spend    \$$spent of \$$ceiling over 7 days"

    last="$(distill_last_run)"
    if [ -z "$last" ]; then
        s_note "last run no run recorded yet"
    else
        line="$(printf '%s' "$last" | jq -r \
            '"\(.end[0:16] | sub("T"; " ")) UTC · \(.status)"
             + " · \(.sessions.kept)/\(.sessions.seen) session(s) · \(.dur // 0)s · $\(.cost * 100 | round / 100)"')"
        case "$(printf '%s' "$last" | jq -r '.status')" in
            ok) s_pass "last run $line" ;;
            *) s_fail "last run $line" ;;
        esac
        # Per-session reasons. "7 seen, 0 kept" reads as a broken job until you
        # can see that six were under minTurns and one had nothing durable in it,
        # and with the reports gone this is the only place that says so.
        while IFS= read -r line; do
            [ -n "$line" ] && dim "           $line"
        done < <(distill_run_last_detail)
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
    distill_run_begin
    _distill_daily_body
    rc=$?
    distill_run_end "$rc" || rc=1
    return "$rc"
}

_distill_daily_body() {
    local since now tmp sysfile schema filtered turns cwd out
    local sess name title mapped date n_items persisted=1

    distill_spend_ok || return 1

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

    distill_render_all
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

# distill_guard_secrets — the sweep follows the content, not the directory. The
# extracts quote the conversation they came from, and MAIN.md is loaded into every
# session, so both are swept and any hit blocks every commit this run would have
# made.
distill_guard_secrets() {
    local d
    command -v gitleaks >/dev/null 2>&1 || {
        warn "gitleaks not installed — skipping the secret sweep"
        return 0
    }
    for d in "$(distill_state_dir)" "$(distill_memory_dir)"; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        if ! gitleaks dir "$d" --redact --no-banner >/dev/null 2>&1; then
            fail "gitleaks found something in $d — not committing"
            return 1
        fi
    done
    return 0
}

# ─── Rubric ───────────────────────────────────────────────────────────────────
#
# The rubric REPLACES the default system prompt. The Skill tool is unavailable
# under `--tools ""`, so the SKILL.md is read as a file here; it still doubles
# as a manually invocable `/distill` in an interactive session.

# distill_rubric — the body of the distill SKILL.md, front matter stripped.
distill_rubric() {
    local deployed repo
    deployed="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}/skills/distill/SKILL.md"
    repo="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}/src/dot_config/claude/skills/distill/SKILL.md"
    if [ -r "$deployed" ]; then
        sed '1{/^---$/,/^---$/d;}' "$deployed"
    elif [ -r "$repo" ]; then
        sed '1{/^---$/,/^---$/d;}' "$repo"
    else
        printf 'Extract durable lessons from Claude Code sessions. Answer only with the schema.\n'
    fi
}
