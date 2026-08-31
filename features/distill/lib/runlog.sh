#!/usr/bin/env bash
# What a run did.
#
# runs.jsonl — a row per night. Per-machine and append-only, which is why it is
# never tracked: two Macs sharing a corpus would conflict on every line.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

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

# distill_log_file — where launchd sends the nightly job's stdout AND stderr
# (both keys in the plist point here). Gitignored: it describes one machine's
# 01:00, and two Macs appending to one file would conflict on every line.
distill_log_file() {
    printf '%s/logs/nightly.log\n' "$(distill_state_dir)"
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
    distill_commit_local "$msg"
    return 0
}
