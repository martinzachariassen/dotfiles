#!/usr/bin/env bats
# What a run costs and what it records. The budget is a rolling 7-day ceiling
# checked in preflight *and* before every session, so a long backfill stops
# part-way — keeping what it paid for — instead of running past it.
#
# Harness in core/testing/distill.bash; engine in features/distill/lib/.

setup() {
    load '../../../core/testing/helper'
    load '../../../core/testing/distill'
    distill_setup
}

# ─── Cost ─────────────────────────────────────────────────────────────────────

@test "the rolling spend ceiling refuses to start a run" {
    load_lib
    printf '{"t":"%s","usd":99}\n' "$(distill_iso_now)" >"$STATE/spend.jsonl"
    run distill_spend_ok
    [ "$status" -ne 0 ]
    [[ "$output" == *"ceiling"* ]] || return 1
}

@test "spend under the ceiling allows a run" {
    load_lib
    printf '{"t":"%s","usd":0.5}\n' "$(distill_iso_now)" >"$STATE/spend.jsonl"
    run distill_spend_ok
    [ "$status" -eq 0 ]
}

@test "spend older than seven days no longer counts" {
    load_lib
    printf '{"t":"%s","usd":99}\n' "$(distill_iso_ago 30)" >"$STATE/spend.jsonl"
    run distill_spend_ok
    [ "$status" -eq 0 ]
}

# spend.jsonl is appended to by a job that can be killed mid-write, so a torn
# line is ordinary. Slurping the file made one bad line abort the parse and the
# total come back 0 — the ceiling then reads "spent nothing, go ahead". A cost
# brake that fails open on its most likely damage is not a brake.
@test "a torn line in the spend log costs that line, not the whole ceiling" {
    load_lib
    {
        printf '{"t":"%s","usd":99}\n' "$(distill_iso_now)"
        printf '{"t":"%s","usd":1.5' "$(distill_iso_now)"
    } >"$STATE/spend.jsonl"
    run distill_spend_ok
    [ "$status" -ne 0 ]
    [[ "$output" == *"ceiling"* ]] || return 1
}

@test "a spend total that cannot be evaluated stops the run rather than waving it through" {
    DISTILL_CONFIG_JSON="$(cfg '{"maxSpendUsd7d":"not-a-number"}')"
    export DISTILL_CONFIG_JSON
    load_lib
    run distill_spend_ok
    [ "$status" -ne 0 ]
}

# a_conversation NAME — a transcript with enough typed turns to be worth a call.
a_conversation() {
    local f="$ROOTS/proj/$1.jsonl" now
    now="$(distill_iso_now)"
    mkdir -p "$ROOTS/proj"
    : >"$f"
    local i
    for i in 1 2 3; do
        jq -nc --arg t "$now" --arg s "$1" --arg i "$i" \
            '{uuid:("u-"+$s+"-"+$i), timestamp:$t,
              type:"user", promptSource:"typed", sessionId:$s, cwd:"/x",
              message:{role:"user", content:[{type:"text", text:"a question"}]}}' \
            >>"$f"
    done
    printf '%s\n' "$f"
}

# A nightly run reads two days and cannot approach the ceiling; `--since 90d`
# reads hundreds of sessions in one go, and a ceiling checked once before any of
# them is not a ceiling.
@test "the ceiling stops a long backfill part-way, and holds the cursor" {
    ROOTS="$BATS_TEST_TMPDIR/transcripts"
    mkdir -p "$ROOTS"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg r "$ROOTS" \
        '{transcriptRoots:[$r], maxSpendUsd7d:1.0}')")"
    export DISTILL_CONFIG_JSON
    load_lib

    a_conversation one >/dev/null
    a_conversation two >/dev/null

    # One session's worth of extraction blows the whole 7-day ceiling.
    distill_claude() {
        printf '{"t":"%s","usd":9.0}\n' "$(distill_iso_now)" >>"$STATE/spend.jsonl"
        printf '%s\n' '{"items":[{"text":"a rule","detail":"why",
                                  "kind":"learnings","topic":"T"}]}'
    }

    distill_run_begin
    run _distill_daily_body
    [ "$status" -eq 0 ]
    [[ "$output" == *"ceiling reached"* ]] || return 1
    # Exactly one session was paid for; the other was never read...
    [[ "$output" == *"1 of 2 session(s)"* ]] || return 1
    # ...so the cursor must not claim the window was read to the end.
    [ ! -f "$STATE/cursor.json" ]
    [[ "$output" == *"cursor held"* ]] || return 1
    # What was already paid for is still saved.
    grep -rq 'a rule' "$STATE/extracts"
}

# `chezdistill -n` is the documented free preview, and it used to consume the
# very window it was previewing: no DRY_RUN guard sat between the harvest loop
# and distill_cursor_write, so the next real run started after the sessions you
# had just asked it to look at.
@test "a dry run does not spend the window it is previewing" {
    ROOTS="$BATS_TEST_TMPDIR/transcripts"
    mkdir -p "$ROOTS"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg r "$ROOTS" '{transcriptRoots:[$r]}')")"
    export DISTILL_CONFIG_JSON
    load_lib
    a_conversation one >/dev/null

    distill_run_begin
    DRY_RUN=1 run _distill_daily_body
    [ "$status" -eq 0 ]
    [ ! -f "$STATE/cursor.json" ]
    [ ! -f "$MEM/MAIN.md" ]
    [ ! -d "$STATE/extracts" ]
}

# One session the model chokes on must not wedge the cursor and re-bill forever.
@test "a single failed model call is forgiven and the cursor still moves" {
    ROOTS="$BATS_TEST_TMPDIR/transcripts"
    mkdir -p "$ROOTS"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg r "$ROOTS" '{transcriptRoots:[$r]}')")"
    export DISTILL_CONFIG_JSON
    load_lib
    a_conversation one >/dev/null
    a_conversation two >/dev/null

    # The first call fails, the second succeeds.
    distill_claude() {
        if [ ! -f "$BATS_TEST_TMPDIR/called" ]; then
            : >"$BATS_TEST_TMPDIR/called"
            return 1
        fi
        printf '%s\n' '{"items":[{"text":"a rule","detail":"why",
                                  "kind":"learnings","topic":"T"}]}'
    }

    distill_run_begin
    run _distill_daily_body
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 of 2 model call(s) failed"* ]] || return 1
    [ -f "$STATE/cursor.json" ]
}

# But every call failing is not this window being unlucky — it is the model being
# unreachable, and launchd not carrying your shell's provider variables is the
# likeliest cause. Advancing over an untried window loses it for good.
@test "every model call failing is an outage, and holds the cursor" {
    ROOTS="$BATS_TEST_TMPDIR/transcripts"
    mkdir -p "$ROOTS"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg r "$ROOTS" '{transcriptRoots:[$r]}')")"
    export DISTILL_CONFIG_JSON
    load_lib
    a_conversation one >/dev/null
    a_conversation two >/dev/null

    distill_claude() { return 1; }

    distill_run_begin
    run _distill_daily_body
    [ "$status" -ne 0 ]
    [[ "$output" == *"outage"* ]] || return 1
    [ ! -f "$STATE/cursor.json" ]
    [[ "$output" == *"cursor held"* ]] || return 1
}

# ─── Run log ──────────────────────────────────────────────────────────────────
#
# The run log exists for the runs nobody watches: a nightly job that fires at
# 01:00 and skips everything leaves no trace anywhere the user looks. There is no
# human-facing report any more, so this record and `--status`, which reads it
# back, are the only place the reason survives.

@test "a run is recorded with what it saw and what it kept" {
    load_lib
    distill_run_begin
    DISTILL_RUN_SEEN=4
    DISTILL_RUN_KEPT=2
    DISTILL_RUN_ITEMS=7
    distill_run_record ok

    [ -f "$STATE/runs.jsonl" ]
    run jq -r '"\(.status) \(.sessions.kept)/\(.sessions.seen) \(.items)"' \
        "$STATE/runs.jsonl"
    [ "$output" = "ok 2/4 7" ]
}

@test "a failed run keeps the reason in the record" {
    load_lib
    distill_run_begin
    distill_fail "claude invocation failed for model sonnet" >/dev/null
    distill_run_record failed

    run jq -r '.status, (.notes[] | .text)' "$STATE/runs.jsonl"
    [[ "$output" == *"failed"* ]] || return 1
    [[ "$output" == *"claude invocation failed for model sonnet"* ]] || return 1
}

# "7 seen, 0 kept" reads as a broken job until you can see that six were under
# minTurns and one had nothing durable in it. --status is the only thing that
# says so, and it reads this.
@test "a skipped session records why, and reads back per session" {
    load_lib
    distill_run_begin
    distill_run_session sess-12345678 2 "too short, no model call" 0
    distill_run_record ok

    run distill_run_last_detail
    [ "$status" -eq 0 ]
    [[ "$output" == *"too short, no model call"* ]] || return 1
    [[ "$output" == *"2 turn(s)"* ]] || return 1
}

@test "records older than the retention window are pruned" {
    load_lib
    jq -nc --arg t "$(distill_iso_ago 200)" '{t:$t, end:$t}' >"$STATE/runs.jsonl"
    jq -nc --arg t "$(distill_iso_now)" '{t:$t, end:$t}' >>"$STATE/runs.jsonl"
    distill_run_prune
    [ "$(wc -l <"$STATE/runs.jsonl" | tr -d ' ')" -eq 1 ]
}

@test "the run log is written before anything is committed" {
    load_lib
    # Both must happen inside distill_run_end, and the record must come first:
    # a record that lands after the commit is only ever committed a day late.
    end="$BATS_TEST_TMPDIR/end.sh"
    distill_fn_body distill_run_end >"$end"
    [ "$(grep -n distill_run_record "$end" | cut -d: -f1)" \
        -lt "$(grep -n distill_commit_local "$end" | cut -d: -f1)" ]
}

# ─── Losing paid work ─────────────────────────────────────────────────────────
#
# Writing the extract is the only step in the job that can lose money: the model
# calls are already billed by the time it runs, and no re-run recovers them. So a
# failure there has to hold the cursor back, or the next run skips the same window
# and the spend is gone for good.

@test "extracts are merged into the day they belong to, without double-counting" {
    load_lib
    # A backfill and a nightly run on the same Mac land in the same shard.
    mkdir -p "$STATE/extracts"
    jq -n --argjson i "[$(item 'already here' s1)]" '{items:$i}' \
        >"$(distill_extract_file 2026-08-22)"
    tmp="$BATS_TEST_TMPDIR/items"
    mkdir -p "$tmp"
    # s1 again (a re-read session) plus a genuinely new one.
    printf '%s\n%s\n' "$(item 'already here' s1)" "$(item 'brand new' s2)" \
        >"$tmp/items-2026-08-22.ndjson"

    distill_run_begin
    run distill_persist_extracts "$tmp"
    [ "$status" -eq 0 ]
    [ "$(jq '.items | length' "$(distill_extract_file 2026-08-22)")" -eq 2 ]
}

@test "a failed extract write is fatal, so the caller can hold the cursor" {
    load_lib
    mkdir -p "$STATE/extracts"
    chmod a-w "$STATE/extracts"
    tmp="$BATS_TEST_TMPDIR/items"
    mkdir -p "$tmp"
    printf '%s\n' "$(item 'would be lost' s1)" >"$tmp/items-2026-08-22.ndjson"

    distill_run_begin
    run distill_persist_extracts "$tmp"
    chmod u+w "$STATE/extracts"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not saved"* ]] || return 1
}
