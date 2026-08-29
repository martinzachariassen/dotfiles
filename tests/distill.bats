#!/usr/bin/env bats
# chezdistill: the behaviour that bash -n and shellcheck cannot see.
#
# The cases that carry the design, and why each exists:
#   split        memory and state are two destinations with nothing in common,
#                and a test that omits either path writes into the live ones
#   secrets      the extracts hold near-verbatim conversation text and MAIN.md is
#                loaded into every session, so the gitleaks sweep covers both
#   determinism  a re-render must be byte-identical, or every run makes a commit
#   promotion    hits >= minHits is what stops one misreading in one conversation
#                becoming a rule applied to every future session
#   cap          MAIN is loaded into every session forever; the limit is a
#                guarantee, not an estimate
#   spend        an unattended nightly job must not be able to bill for a week
#   undo         MAIN.md is derived, so undo reverts the corpus and re-renders

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    BIN="$REPO_ROOT/scripts/bin/distill.sh"
    LIB="$REPO_ROOT/scripts/lib/distill.sh"
    command -v jq >/dev/null || skip "jq not installed"
    command -v git >/dev/null || skip "git not installed"

    # Memory and state are real local directories in production, so they get real
    # temp directories here — and never $HOME, which holds the live ones.
    MEM="$(mktemp -d)"
    STATE="$(mktemp -d)"

    export DISTILL_CONFIG_JSON
    DISTILL_CONFIG_JSON="$(cfg)"
}

# cfg [EXTRA-JSON] — the config every test starts from, optionally overridden.
# Going through one helper is what keeps a test from silently falling back to the
# real ~/.config/claude/memory by omitting a path.
cfg() {
    local extra='{}'
    [ $# -gt 0 ] && extra="$1"
    jq -nc --arg m "$MEM" --arg s "$STATE" \
        --argjson extra "$extra" '{
        memoryPath:$m, statePath:$s,
        transcriptRoots:[],
        mainCapBytes:6144, minHits:2, demoteAfterDays:9999,
        maxSpendUsd7d:25.0, maxBudgetUsd:1.0, minTurns:3} * $extra'
}

teardown() {
    [ -n "${MEM:-}" ] && rm -rf "$MEM"
    [ -n "${STATE:-}" ] && rm -rf "$STATE"
    return 0
}

# Source the engine with the logging vocabulary it expects.
load_lib() {
    # shellcheck source=../scripts/lib/log.sh
    . "$REPO_ROOT/scripts/lib/log.sh"
    ui_init_logging
    ui_init_status
    # shellcheck source=../scripts/lib/distill.sh
    . "$LIB"
    DISTILL_MEMORY="$MEM"
    DISTILL_STATE="$STATE"
}

# A bare `! grep …` in a test body is exempt from set -e (POSIX: the return
# value is being inverted), so bats never sees it fail — the assertion passes no
# matter what the file contains. tests/zshrc-wiring.bats documents the same trap.
# Negative assertions must go through this.
refute_file_contains() {
    if grep -q "$2" "$1"; then
        echo "unexpected match for '$2' in $1"
        return 1
    fi
}

# extract DATE JSON-ARRAY — the day's extract, in the pre-sharding `<date>.json`
# layout. Deliberately the OLD name: every derivation test then doubles as proof
# that a corpus written before per-host sharding still reads back identically.
extract() {
    mkdir -p "$STATE/extracts"
    jq -n --argjson items "$2" '{items:$items}' >"$STATE/extracts/$1.json"
}

# item TEXT SESSION [TOPIC] — hits count distinct sessions, so SESSION is what
# decides whether a rule is promoted.
item() {
    jq -nc --arg t "$1" --arg s "$2" --arg p "${3:-T}" \
        '{text:$t, detail:"detail", kind:"learnings", topic:$p, session:$s}'
}

# ─── Script guards ────────────────────────────────────────────────────────────

@test "hard-fails when log.sh is missing" {
    tmp="$(mktemp -d)"
    cp "$BIN" "$tmp/distill.sh"
    run bash "$tmp/distill.sh"
    rm -rf "$tmp"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]]
    [[ "$output" == *"log.sh"* ]]
}

@test "--help prints usage and exits 0" {
    run bash "$BIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: chezdistill"* ]]
}

@test "unknown option exits 2" {
    run bash "$BIN" --nope
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "--since rejects a missing value" {
    run bash "$BIN" --since
    [ "$status" -eq 2 ]
}

# --logs and --runs take an OPTIONAL count, which is the parser's one real
# hazard: a naive `shift` eats whatever follows, and the damage is silent —
# `--logs -f` quietly stops following, `--logs --nope` quietly stops erroring.
# The lookahead therefore consumes only a bare integer, and these pin that.

@test "an optional count never swallows the flag behind it" {
    run bash "$BIN" --logs --nope
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option: --nope"* ]]
}

@test "a non-numeric count is refused rather than read as a flag" {
    run bash "$BIN" --runs 7d
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option: 7d"* ]]

    run bash "$BIN" --runs=abc
    [ "$status" -eq 2 ]
}

@test "-f outside --logs is refused, not ignored" {
    run bash "$BIN" --status -f
    [ "$status" -eq 2 ]
    [[ "$output" == *"only applies to --logs"* ]]
}

# ─── Preflight ────────────────────────────────────────────────────────────────
#
# Both destinations are ordinary local directories the job owns outright, so
# preflight creates them rather than refusing. The one failure left is a path it
# cannot actually write — and that has to stop the run, because MAIN.md is what
# every future session loads.

@test "preflight creates the two destinations it was given" {
    load_lib
    m="$BATS_TEST_TMPDIR/new-mem"
    s="$BATS_TEST_TMPDIR/new-state"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg m "$m" --arg s "$s" \
        '{memoryPath:$m, statePath:$s}')")"
    _DISTILL_CFG=""
    unset DISTILL_MEMORY DISTILL_STATE
    run distill_preflight
    [ "$status" -eq 0 ]
    [ -d "$m" ]
    [ -d "$s" ]
}

@test "preflight fails on a destination it cannot write" {
    load_lib
    ro="$BATS_TEST_TMPDIR/ro-pre"
    mkdir -p "$ro"
    chmod a-w "$ro"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg m "$ro/mem" '{memoryPath:$m}')")"
    _DISTILL_CFG=""
    unset DISTILL_MEMORY DISTILL_STATE
    run distill_preflight
    chmod u+w "$ro"
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot write"* ]]
}

@test "the memory tier is written where Claude reads it" {
    load_lib
    extract 2026-08-22 "[$(item 'lives in memory' s1)]"
    extract 2026-08-23 "[$(item 'lives in memory' s2)]"
    distill_render_all
    [ -f "$MEM/MAIN.md" ]
    [ -f "$MEM/Topics/T.md" ]
    [ -f "$MEM/Candidates.md" ]
    # Nothing generated belongs beside the inputs.
    [ ! -e "$STATE/MAIN.md" ]
    [ ! -e "$STATE/Topics" ]
}

# MAIN carries the rule; Topics carries the reasoning. The pointer is the only
# thing connecting them, so its absence would make the whole second tier dead.
@test "MAIN.md points at the Topics beside it" {
    load_lib
    distill_render_main
    grep -q 'Topics/<Topic>.md' "$MEM/MAIN.md"
}

@test "entry ids ignore case, spacing and trailing punctuation" {
    load_lib
    a="$(distill_entry_id 'Use rg, never grep.')"
    b="$(distill_entry_id '  use   RG, never grep  ')"
    [ -n "$a" ]
    [ "$a" = "$b" ]
}

# ─── Derivation and the promotion gate ────────────────────────────────────────

@test "hits count distinct sessions, not sightings" {
    load_lib
    extract 2026-08-22 "[$(item 'same rule' s1),$(item 'same rule' s1)]"
    run distill_derive
    [[ "$output" == *'"hits":1'* ]]
}

@test "a single sighting stays out of MAIN and lands in Candidates" {
    load_lib
    extract 2026-08-22 "[$(item 'seen once' s1)]"
    distill_render_main
    distill_render_inbox
    refute_file_contains "$MEM/MAIN.md" 'seen once'
    grep -q 'seen once' "$MEM/Candidates.md"
}

@test "a second sighting promotes the entry into MAIN" {
    load_lib
    extract 2026-08-22 "[$(item 'promote me' s1)]"
    extract 2026-08-23 "[$(item 'promote me' s2)]"
    distill_render_main
    grep -q 'promote me' "$MEM/MAIN.md"
}

# Topics is the free tier and deliberately wider than MAIN: a rule still waiting
# for its second sighting is worth reading once you have gone looking for it.
# The model names topics freely and has produced "Git/GitHub". Left alone the
# slash redirects the write into a directory that does not exist, and the topic
# is lost with no error anyone sees.
@test "a topic with a slash in its name still gets a file" {
    load_lib
    extract 2026-08-22 "[$(item 'slashed topic' s1 'Git/GitHub')]"
    distill_render_topics
    [ -f "$MEM/Topics/Git-GitHub.md" ]
    grep -q 'slashed topic' "$MEM/Topics/Git-GitHub.md"
}

@test "Topics carries the detail for entries MAIN has not promoted" {
    load_lib
    extract 2026-08-22 "[$(item 'not promoted yet' s1)]"
    distill_render_topics
    grep -q 'not promoted yet' "$MEM/Topics/T.md"
    grep -q 'detail' "$MEM/Topics/T.md"
}

# ─── Two Macs, one remote ─────────────────────────────────────────────────────
#
# The corpus is the only thing in the state repo worth keeping, and it is merged
# in place. If two machines wrote the same path they would conflict on every
# rebase, the push fallback would give up silently, and the backup would stop —
# leaving the telemetry, which nobody needs, as the only thing being synced.

@test "this machine writes its own share of a day" {
    load_lib
    f="$(distill_extract_file 2026-08-22)"
    [ "$(dirname "$f")" = "$STATE/extracts" ]
    [[ "$(basename "$f")" == "2026-08-22."*".json" ]]
    [ "$(basename "$f")" != "2026-08-22.json" ]
}

@test "a day both Macs contributed to derives as one day" {
    load_lib
    mkdir -p "$STATE/extracts"
    jq -n --argjson i "[$(item 'shared rule' s1)]" '{items:$i}' \
        >"$STATE/extracts/2026-08-22.mac-one.json"
    jq -n --argjson i "[$(item 'shared rule' s2)]" '{items:$i}' \
        >"$STATE/extracts/2026-08-22.mac-two.json"

    run distill_derive
    [[ "$output" == *'"hits":2'* ]]
    # The host suffix must not leak into the date the renderer sorts and ages by.
    [[ "$output" == *'"first_seen":"2026-08-22"'* ]]
    [[ "$output" == *'"last_seen":"2026-08-22"'* ]]
}

@test "retention ages a host-scoped extract by its date, not its filename" {
    load_lib
    old_date="$(distill_iso_ago 200 | cut -c1-10)"
    mkdir -p "$STATE/extracts"
    jq -n '{items:[{text:"a rule", detail:"why", kind:"learnings", topic:"T",
                    session:"s1", evidence:"a quoted line", cwd:"/x"}]}' \
        >"$STATE/extracts/$old_date.mac-one.json"
    distill_prune_extracts
    run jq -r '.items[0] | has("evidence")' "$STATE/extracts/$old_date.mac-one.json"
    [ "$output" = "false" ]
}

# Every one of these is append-only, so two Macs pushing would conflict on all of
# them — and none can be regenerated onto a new machine anyway, which is the only
# reason to back anything up here.
@test "per-machine telemetry is never committed" {
    load_lib
    distill_state_repo_init
    printf '{"t":"x"}\n' >"$STATE/runs.jsonl"
    printf '{"t":"x"}\n' >"$STATE/spend.jsonl"
    distill_cursor_write "2026-08-22T00:00:00Z"
    extract 2026-08-22 "[$(item 'kept' s1)]"
    distill_commit_local "chore(distill): test"

    run git -C "$STATE" ls-files
    [[ "$output" != *"runs.jsonl"* ]]
    [[ "$output" != *"spend.jsonl"* ]]
    [[ "$output" != *"cursor.json"* ]]
    # ...and the one thing that cannot be regenerated still is.
    [[ "$output" == *"extracts/"* ]]
}

# ─── Determinism and the cap ──────────────────────────────────────────────────

@test "rendering MAIN twice is byte-identical" {
    load_lib
    extract 2026-08-22 "[$(item 'rule one' s1),$(item 'rule two' s1 U)]"
    extract 2026-08-23 "[$(item 'rule one' s2),$(item 'rule two' s2 U)]"
    distill_render_main "$BATS_TEST_TMPDIR/first.md"
    distill_render_main "$BATS_TEST_TMPDIR/second.md"
    cmp "$BATS_TEST_TMPDIR/first.md" "$BATS_TEST_TMPDIR/second.md"
}

@test "the cap is a guarantee and Pinned.md survives it" {
    load_lib
    printf '# Pinned\n\n- keep me forever\n' >"$(distill_pinned_file)"
    items="["
    for i in 1 2 3 4 5 6 7 8 9; do
        items="$items$(item "a fairly long rule number $i that eats into the byte budget" s1),"
        items="$items$(item "a fairly long rule number $i that eats into the byte budget" s2),"
    done
    items="${items%,}]"
    extract 2026-08-22 "$items"

    # Above the fixed preamble (header + Topics pointer, both of which name a
    # path) but well under the ~550 bytes the nine rules need, so the cap has to
    # actually truncate rather than happening to fit.
    DISTILL_CONFIG_JSON="$(cfg '{"mainCapBytes":700}')"
    _DISTILL_CFG=""
    distill_render_main
    size="$(wc -c <"$MEM/MAIN.md" | tr -d ' ')"
    [ "$size" -le 700 ]
    # Pinned is never what gets sacrificed to the cap...
    grep -q 'keep me forever' "$MEM/MAIN.md"
    # ...and the rules are: not all nine fit. grep -c is exempt from set -e when
    # it matches nothing, so count the lines rather than trusting its exit code.
    n="$(grep 'eats into the byte budget' "$MEM/MAIN.md" | wc -l | tr -d ' ')"
    [ "$n" -ge 1 ]
    [ "$n" -lt 9 ]
}

# The floor. Rules qualified and not one of them reached the file: the only way
# that happens is Pinned.md eating the whole budget, and silently shipping an
# empty MAIN.md is this job's signature failure — a real result replaced by
# nothing, reported ok. Refusing leaves the last good MAIN.md in place.
@test "MAIN.md is not silently emptied when qualifying rules cannot fit" {
    load_lib
    head -c 900 /dev/zero | tr '\0' 'x' >"$(distill_pinned_file)"
    extract 2026-08-22 "[$(item "a rule that earned its place" s1),
                         $(item "a rule that earned its place" s2)]"
    DISTILL_CONFIG_JSON="$(cfg '{"mainCapBytes":700}')"
    _DISTILL_CFG=""
    printf 'the previous good render\n' >"$MEM/MAIN.md"
    run distill_render_main
    [ "$status" -ne 0 ]
    # The old file is still there, untouched — stale beats empty.
    grep -q 'the previous good render' "$MEM/MAIN.md"
}

# An empty corpus is a different thing entirely: nothing has cleared the
# promotion gate yet, which is the normal state of a young install and must stay
# a clean success or every first run reports a failure.
@test "a corpus with nothing promoted yet still renders a clean MAIN.md" {
    load_lib
    extract 2026-08-22 "[$(item "seen only once so far" s1)]"
    run distill_render_main
    [ "$status" -eq 0 ]
    grep -q 'Generated by chezdistill' "$MEM/MAIN.md"
}

# last_seen is the first ten characters of a filename and nothing validates it.
# A bare tonumber on one stray file aborted the WHOLE jq, so every consumer saw
# an empty stream and MAIN.md rendered with no rules at all — successfully.
@test "a stray file in the corpus cannot empty the scoring stream" {
    load_lib
    extract 2026-08-22 "[$(item "a rule that earned its place" s1),
                         $(item "a rule that earned its place" s2)]"
    jq -n '{items:[]}' >"$STATE/extracts/notadate.json"
    run distill_render_main
    [ "$status" -eq 0 ]
    grep -q 'a rule that earned its place' "$MEM/MAIN.md"
}

# ─── Cost ─────────────────────────────────────────────────────────────────────

@test "the rolling spend ceiling refuses to start a run" {
    load_lib
    printf '{"t":"%s","usd":99}\n' "$(distill_iso_now)" >"$STATE/spend.jsonl"
    run distill_spend_ok
    [ "$status" -ne 0 ]
    [[ "$output" == *"ceiling"* ]]
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
    [[ "$output" == *"ceiling"* ]]
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
    [[ "$output" == *"ceiling reached"* ]]
    # Exactly one session was paid for; the other was never read...
    [[ "$output" == *"1 of 2 session(s)"* ]]
    # ...so the cursor must not claim the window was read to the end.
    [ ! -f "$STATE/cursor.json" ]
    [[ "$output" == *"cursor held"* ]]
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
    [[ "$output" == *"1 of 2 model call(s) failed"* ]]
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
    [[ "$output" == *"outage"* ]]
    [ ! -f "$STATE/cursor.json" ]
    [[ "$output" == *"cursor held"* ]]
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
    [[ "$output" == *"failed"* ]]
    [[ "$output" == *"claude invocation failed for model sonnet"* ]]
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
    [[ "$output" == *"too short, no model call"* ]]
    [[ "$output" == *"2 turn(s)"* ]]
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
    awk '/^distill_run_end\(\) \{/,/^\}/' "$LIB" >"$end"
    [ "$(grep -n distill_run_record "$end" | cut -d: -f1)" \
        -lt "$(grep -n distill_commit_local "$end" | cut -d: -f1)" ]
}

# ─── Secrets ──────────────────────────────────────────────────────────────────
#
# The extracts hold near-verbatim conversation text, and MAIN.md is loaded into
# every session. Both destinations have to be swept, and the state repo is the
# one that can be given a remote.

@test "the secret sweep covers state and memory" {
    load_lib
    guard="$BATS_TEST_TMPDIR/guard.sh"
    awk '/^distill_guard_secrets\(\) \{/,/^\}/' "$LIB" >"$guard"
    grep -q 'distill_state_dir' "$guard"
    grep -q 'distill_memory_dir' "$guard"
}

# ─── Failed writes must be loud ───────────────────────────────────────────────
#
# The 01:00 launchd run spent weeks reporting "ok, 1 warning(s)" while macOS
# refused every write. Two things allowed that: `[ -w ]` passes under TCC because
# the POSIX bits are fine, and a body that returns 0 outvoted the failures
# recorded underneath it.

@test "a writable-looking but unwritable dir is caught by an actual write" {
    load_lib
    ro="$BATS_TEST_TMPDIR/ro"
    mkdir -p "$ro"
    chmod a-w "$ro"
    run distill_can_write "$ro"
    chmod u+w "$ro"
    [ "$status" -ne 0 ]
}

@test "a run with any recorded failure is never reported ok" {
    load_lib
    distill_run_begin
    distill_fail "could not write MAIN.md" >/dev/null
    distill_run_end 0 >/dev/null 2>&1 || true
    run distill_last_run
    [[ "$output" == *'"status":"failed"'* ]]
}

@test "a failed MAIN.md write is recorded, not swallowed" {
    load_lib
    ro="$BATS_TEST_TMPDIR/ro-main"
    mkdir -p "$ro"
    chmod a-w "$ro"
    distill_run_begin
    run distill_render_main "$ro/MAIN.md"
    chmod u+w "$ro"
    [ "$status" -ne 0 ]
    grep -q 'could not write' "$_DISTILL_EVENTS"
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
    [[ "$output" == *"not saved"* ]]
}

# ─── Retention ────────────────────────────────────────────────────────────────
#
# The obvious reading of extractRetentionDays — delete old extracts — would erase
# the memory, because hits and first_seen are derived from them on every render.
# An established rule would drop back under the promotion gate and be evicted
# from MAIN.md, so the corpus would forget exactly what has been true longest.

@test "retention drops the quote and the path, never the rule" {
    load_lib
    old_date="$(distill_iso_ago 200 | cut -c1-10)"
    mkdir -p "$STATE/extracts"
    jq -n '{items:[{text:"a rule", detail:"why", kind:"learnings", topic:"T",
                    session:"s1", evidence:"a quoted line", cwd:"/Users/x/secret",
                    origin:"personal", host:"oldmac"}]}' \
        >"$STATE/extracts/$old_date.json"
    distill_prune_extracts

    run jq -r '.items[0] | has("evidence"), has("cwd"), has("origin"), has("host")' \
        "$STATE/extracts/$old_date.json"
    [[ "$output" != *"true"* ]]
    run jq -r '.items[0].text' "$STATE/extracts/$old_date.json"
    [ "$output" = "a rule" ]
}

@test "retention leaves a rule promoted after the quote is aged out" {
    load_lib
    old_date="$(distill_iso_ago 200 | cut -c1-10)"
    mkdir -p "$STATE/extracts"
    for sess in s1 s2; do
        jq -n --arg s "$sess" '{items:[{text:"survives retention", detail:"why",
            kind:"learnings", topic:"T", session:$s, evidence:"quote", cwd:"/x"}]}' \
            >"$STATE/extracts/$old_date-$sess.json"
    done
    # demoteAfterDays would evict it for age; this is about hits surviving.
    DISTILL_CONFIG_JSON="$(cfg '{"demoteAfterDays":99999}')"
    _DISTILL_CFG=""
    distill_prune_extracts
    run distill_derive
    [[ "$output" == *'"hits":2'* ]]
}

@test "recent extracts keep their evidence" {
    load_lib
    extract 2026-08-22 "[$(item 'recent' s1)]"
    jq '.items[0] += {evidence:"keep me", cwd:"/x"}' "$STATE/extracts/2026-08-22.json" \
        >"$STATE/e.tmp" && mv "$STATE/e.tmp" "$STATE/extracts/2026-08-22.json"
    distill_prune_extracts
    run jq -r '.items[0].evidence' "$STATE/extracts/2026-08-22.json"
    [ "$output" = "keep me" ]
}

# ─── Pinned.md ────────────────────────────────────────────────────────────────

@test "Pinned.md lives with the inputs and is committed with them" {
    load_lib
    printf '# Pinned\n\n- keep me forever\n' >"$(distill_pinned_file)"
    distill_render_main
    grep -q 'keep me forever' "$MEM/MAIN.md"

    distill_commit_local "chore(distill): test"
    run git -C "$STATE" ls-files
    [[ "$output" == *"Pinned.md"* ]]
}

# A rule added to .gitignore after a repo already exists must both reach that
# repo and untrack what it now covers. Neither is automatic, and the failure is
# invisible until the file has already been pushed somewhere.
@test "an ignore rule added later untracks what it now covers" {
    load_lib
    distill_state_repo_init
    printf 'logs/\n' >"$STATE/.gitignore"
    distill_cursor_write "2026-08-22T00:00:00Z"
    git -C "$STATE" add -f cursor.json >/dev/null 2>&1
    git -C "$STATE" -c commit.gpgsign=false -c user.name=t -c user.email=t@t \
        commit -q -m "before" >/dev/null 2>&1

    distill_state_repo_init
    grep -qxF 'cursor.json' "$STATE/.gitignore"
    run git -C "$STATE" ls-files
    [[ "$output" != *"cursor.json"* ]]
}

@test "the cursor is never committed — it is meaningless on another machine" {
    load_lib
    distill_cursor_write "2026-08-22T00:00:00Z"
    printf 'x\n' >"$STATE/extracts-marker"
    distill_commit_local "chore(distill): test"
    run git -C "$STATE" ls-files
    [[ "$output" != *"cursor.json"* ]]
}

# A global url.<ssh>.pushInsteadOf rewrites HTTPS pushes to SSH, and this
# machine's key is behind 1Password. At 01:00 the agent is locked, so the push
# fails and the backup silently stops happening. The repo opts itself out.
@test "an https remote gets a matching push url" {
    load_lib
    distill_state_repo_init
    git -C "$STATE" remote add origin https://example.invalid/x.git
    distill_state_repo_pushurl
    [ "$(git -C "$STATE" config --get remote.origin.pushurl)" = "https://example.invalid/x.git" ]
}

@test "an ssh remote is left exactly as configured" {
    load_lib
    distill_state_repo_init
    git -C "$STATE" remote add origin git@example.invalid:x.git
    distill_state_repo_pushurl
    [ -z "$(git -C "$STATE" config --get remote.origin.pushurl 2>/dev/null)" ]
}

@test "an existing push url is never overwritten" {
    load_lib
    distill_state_repo_init
    git -C "$STATE" remote add origin https://example.invalid/x.git
    git -C "$STATE" config remote.origin.pushurl git@chosen.invalid:x.git
    distill_state_repo_pushurl
    [ "$(git -C "$STATE" config --get remote.origin.pushurl)" = "git@chosen.invalid:x.git" ]
}

# ─── Undo ─────────────────────────────────────────────────────────────────────
#
# MAIN.md is derived, so undo reverts the extract corpus that produced it
# and renders again. Reverting the rendered file instead would leave it free to
# disagree with the corpus on the next run.

# Signing is pinned off in the repo itself, not inherited: a global
# commit.gpgsign backed by 1Password raises a GUI prompt, and the 01:00 launchd
# run has nobody to approve it. GIT_CONFIG_GLOBAL forces the case the machine
# this runs on would otherwise only hit at night.
@test "the state repo commits without a signing agent, and has no remote" {
    load_lib
    printf '[commit]\n\tgpgsign = true\n[gpg]\n\tformat = ssh\n' \
        >"$BATS_TEST_TMPDIR/gitconfig"
    printf '[user]\n\tsigningkey = /nonexistent\n' >>"$BATS_TEST_TMPDIR/gitconfig"
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"

    extract 2026-08-22 "[$(item 'committed' s1)]"
    distill_commit_local "chore(distill): test"
    [ "$(git -C "$STATE" rev-list --count HEAD)" -eq 1 ]
    [ -z "$(git -C "$STATE" remote)" ]
}

@test "logs are kept out of the state repo" {
    load_lib
    mkdir -p "$STATE/logs"
    printf 'noise\n' >"$STATE/logs/nightly.log"
    extract 2026-08-22 "[$(item 'committed' s1)]"
    distill_commit_local "chore(distill): test"
    run git -C "$STATE" ls-files
    [[ "$output" != *"logs/nightly.log"* ]]
}

# The generated notes all say "fix a wrong rule by editing Pinned.md". Until
# something creates it that instruction points at nothing.
@test "Pinned.md is seeded once and never overwritten" {
    load_lib
    distill_seed_pinned
    [ -f "$STATE/Pinned.md" ]
    printf -- '- mine\n' >"$STATE/Pinned.md"
    distill_seed_pinned
    grep -qx -- '- mine' "$STATE/Pinned.md"
}

# The remote is opened on a machine that has none of this set up — which is the
# whole point of a backup — so the repo has to carry its own restore procedure.
@test "the state repo carries a README with the restore procedure" {
    load_lib
    extract 2026-08-22 "[$(item 'committed' s1)]"
    distill_commit_local "chore(distill): test"

    grep -q 'chezdistill --render' "$STATE/README.md"
    grep -q '~/.local/state/chezdistill' "$STATE/README.md"
    git -C "$STATE" ls-files | grep -qx 'README.md'
}

# A clone line naming a remote the repo does not push to is worse than no clone
# line, so it is read back from git rather than written from config.
@test "the README names the remote git actually has" {
    load_lib
    git -C "$STATE" init -q
    git -C "$STATE" remote add origin https://example.invalid/claude-memory.git
    distill_render_state_readme
    grep -q 'https://example.invalid/claude-memory' "$STATE/README.md"
}

# README.md is tracked, so two Macs that spell one remote differently would
# rewrite this file against each other every night — a commit that changes
# nothing, and a merge conflict in the one file that should never have one.
@test "one remote spelled two ways renders one README" {
    load_lib
    git -C "$STATE" init -q
    git -C "$STATE" remote add origin git@github.com:Me/Claude-Memory.git
    distill_render_state_readme
    ssh_form="$(cat "$STATE/README.md")"

    git -C "$STATE" remote set-url origin https://github.com/me/claude-memory
    distill_render_state_readme
    [ "$ssh_form" = "$(cat "$STATE/README.md")" ]
}

@test "rendering the state README twice is byte-identical" {
    load_lib
    distill_render_state_readme "$STATE/one.md"
    distill_render_state_readme "$STATE/two.md"
    cmp "$STATE/one.md" "$STATE/two.md"
}

@test "reverting the state repo takes the rule back out of MAIN" {
    load_lib
    extract 2026-08-22 "[$(item 'first' s1)]"
    distill_commit_local "chore(distill): one"
    extract 2026-08-23 "[$(item 'first' s2)]"
    distill_render_main
    grep -q 'first' "$MEM/MAIN.md"

    distill_commit_local "chore(distill): two"
    git -C "$STATE" revert --no-edit HEAD >/dev/null 2>&1
    distill_render_main
    refute_file_contains "$MEM/MAIN.md" '^- first'
}

# ─── Dry run ──────────────────────────────────────────────────────────────────

@test "DRY_RUN makes no model call" {
    load_lib
    stub="$(mktemp -d)"
    printf '#!/bin/sh\necho CALLED >>"%s/called"\n' "$stub" >"$stub/claude"
    chmod +x "$stub/claude"
    DRY_RUN=1 PATH="$stub:$PATH" run distill_claude sonnet /dev/null /dev/null prompt </dev/null
    [ ! -f "$stub/called" ]
    rm -rf "$stub"
}

# The caller parses this function's stdout as the model's answer. A progress line
# printed there is parsed as JSON, and a dry run then reports "nothing durable in
# it" for every session regardless of what is in them.
@test "DRY_RUN keeps its notice off the captured stdout" {
    load_lib
    out="$(DRY_RUN=1 distill_claude sonnet /dev/null /dev/null prompt </dev/null 2>/dev/null)"
    run jq -e '.' <<<"$out"
    [ "$status" -eq 0 ]
}

# ─── Setup ────────────────────────────────────────────────────────────────────
#
# --setup turns the feature on for this Mac and nothing more: the module list, an
# apply, the nightly timer. It must stay free of API calls, and -n must leave the
# machine exactly as it found it.

# setup_env — a fake HOME with a chezmoi config, plus chezmoi/launchctl stubs so
# no test can reach the real config, the real apply, or the real launchd.
# $1 is the TOML module list literal; CHEZMOI_DATA mirrors it as JSON.
setup_env() {
    SETUP_HOME="$BATS_TEST_TMPDIR/home"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$SETUP_HOME/.config/chezmoi" "$STUBS"

    cat >"$SETUP_HOME/.config/chezmoi/chezmoi.toml" <<EOF
sourceDir = "/x"

[data]
    name        = "CI"
    modules     = $1
EOF
    printf '#!/usr/bin/env bash\n[ "$1" = data ] && { printf "%%s" "${CHEZMOI_DATA:-{\\}}"; exit 0; }\necho "STUB chezmoi $*" >>"%s/chezmoi.log"\nexit 0\n' \
        "$STUBS" >"$STUBS/chezmoi"
    printf '#!/usr/bin/env bash\necho "STUB launchctl $*" >>"%s/launchctl.log"\nexit 0\n' \
        "$STUBS" >"$STUBS/launchctl"
    chmod +x "$STUBS/chezmoi" "$STUBS/launchctl"

    # The plist is present by default: a missing one is itself a reason to apply,
    # which would mask what most of these tests are actually asserting.
    mkdir -p "$SETUP_HOME/Library/LaunchAgents"
    : >"$SETUP_HOME/Library/LaunchAgents/no.mlz.chezdistill.nightly.plist"

    CHEZMOI_DATA="$(printf '%s' "$1" | jq -c '{modules: .}')"
    export CHEZMOI_DATA
}

# run_setup FLAGS… — --setup against the fake HOME, stubs first on PATH.
run_setup() {
    HOME="$SETUP_HOME" PATH="$STUBS:$PATH" YES=1 run bash "$BIN" --setup "$@"
}

@test "--setup -n creates nothing and enables nothing" {
    setup_env '["macApps"]'
    run_setup -n
    [ "$status" -eq 0 ]
    grep -q 'modules     = \["macApps"\]$' "$SETUP_HOME/.config/chezmoi/chezmoi.toml"
    [ ! -f "$STUBS/chezmoi.log" ]
    [ ! -e "$MEM/MAIN.md" ]
}

@test "--setup appends claudeDistiller and keeps the other modules" {
    setup_env '["macApps", "theme"]'
    run_setup
    [ "$status" -eq 0 ]
    grep -q 'modules     = \["macApps", "theme", "claudeDistiller"\]$' \
        "$SETUP_HOME/.config/chezmoi/chezmoi.toml"
    grep -q 'apply --force' "$STUBS/chezmoi.log"
}

@test "--setup handles an empty module list" {
    setup_env '[]'
    run_setup
    [ "$status" -eq 0 ]
    grep -q 'modules     = \["claudeDistiller"\]$' \
        "$SETUP_HOME/.config/chezmoi/chezmoi.toml"
}

@test "--setup is idempotent: an enabled module triggers no apply" {
    setup_env '["macApps", "claudeDistiller"]'
    run_setup
    [ "$status" -eq 0 ]
    grep -q 'modules     = \["macApps", "claudeDistiller"\]$' \
        "$SETUP_HOME/.config/chezmoi/chezmoi.toml"
    [ ! -f "$STUBS/chezmoi.log" ]
}

@test "--setup offers the apply when the nightly plist was never rendered" {
    [ "$(uname -s)" = "Darwin" ] || skip "launchd agents are macOS-only"
    setup_env '["macApps", "claudeDistiller"]'
    rm -f "$SETUP_HOME/Library/LaunchAgents/"*.plist
    run_setup
    [ "$status" -eq 0 ]
    grep -q 'apply --force' "$STUBS/chezmoi.log"
}

# The apply rewrites the global persona to @-import MAIN.md, and an import that
# resolves to nothing is a rough edge in every session until the first nightly
# run. Seeding it costs no API call.
@test "--setup seeds a MAIN.md for the persona to import" {
    setup_env '["macApps"]'
    run_setup
    [ "$status" -eq 0 ]
    [ -f "$MEM/MAIN.md" ]
    grep -q 'Generated by chezdistill' "$MEM/MAIN.md"
}

# ─── Transcript window ────────────────────────────────────────────────────────
#
# The cursor is what lets a laptop that slept through 01:00 lose nothing, but it
# only works if the file scan reaches as far back as the cursor points. A fixed
# window silently defeats it: the sessions from the days it slept are exactly the
# ones whose transcripts stopped being written.

# a_transcript AGE_DAYS — an empty transcript with an mtime AGE_DAYS in the past.
a_transcript() {
    local f="$ROOTS/proj/session-$1.jsonl"
    mkdir -p "$ROOTS/proj"
    : >"$f"
    touch -t "$(date -u -v-"$1"d +%Y%m%d0000 2>/dev/null ||
        date -u -d "$1 days ago" +%Y%m%d0000)" "$f"
    printf '%s\n' "$f"
}

window_setup() {
    ROOTS="$BATS_TEST_TMPDIR/transcripts"
    mkdir -p "$ROOTS"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg r "$ROOTS" '{transcriptRoots:[$r]}')")"
    export DISTILL_CONFIG_JSON
    load_lib
}

@test "a one-day cursor keeps the scan narrow" {
    window_setup
    a_transcript 0 >/dev/null
    a_transcript 6 >/dev/null
    run distill_session_files "$(distill_iso_ago 1)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"session-0.jsonl"* ]]
    [[ "$output" != *"session-6.jsonl"* ]]
}

@test "a week-old cursor reaches the week-old transcripts" {
    window_setup
    a_transcript 0 >/dev/null
    a_transcript 6 >/dev/null
    run distill_session_files "$(distill_iso_ago 7)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"session-0.jsonl"* ]]
    [[ "$output" == *"session-6.jsonl"* ]]
}

@test "an unparseable cursor falls back to a narrow window, not to everything" {
    window_setup
    a_transcript 0 >/dev/null
    a_transcript 6 >/dev/null
    run distill_session_files "not-a-timestamp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"session-0.jsonl"* ]]
    [[ "$output" != *"session-6.jsonl"* ]]
}

@test "subagent transcripts stay out however wide the window" {
    window_setup
    mkdir -p "$ROOTS/proj/subagents"
    : >"$ROOTS/proj/subagents/sub.jsonl"
    run distill_session_files "$(distill_iso_ago 30)"
    [ "$status" -eq 0 ]
    [[ "$output" != *"sub.jsonl"* ]]
}

# ─── Somewhere to read from ───────────────────────────────────────────────────
#
# This job reported `status: ok` every night of its life with transcriptRoots
# pointing at a directory that has never existed. Nothing caught it, because
# "nothing new in tonight's window" and "nothing reachable, ever" produced
# byte-identical output — every precondition in the engine guarded an output,
# and none guarded an input. These pin the distinction apart.

@test "a root that does not exist fails the run, and is named" {
    ROOTS="$BATS_TEST_TMPDIR/nowhere"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg r "$ROOTS" '{transcriptRoots:[$r]}')")"
    export DISTILL_CONFIG_JSON
    load_lib
    distill_run_begin
    run _distill_daily_body
    [ "$status" -ne 0 ]
    [[ "$output" == *"do not exist"* ]]
    [[ "$output" == *"nowhere"* ]]
}

@test "a root that exists but holds no transcripts fails the run" {
    window_setup
    distill_run_begin
    run _distill_daily_body
    [ "$status" -ne 0 ]
    [[ "$output" == *"no transcripts"* ]]
}

# The counterweight, and the more important half: a quiet night must stay quiet.
@test "zero sessions in the window is still an ok run" {
    window_setup
    a_transcript 30 >/dev/null
    distill_run_begin
    run _distill_daily_body
    [ "$status" -eq 0 ]
    [[ "$output" != *"no transcripts"* ]]
}

# The bats suite configures no roots at all, and so does anyone reading the
# corpus on a machine that has never run Claude Code. Unconfigured is a choice;
# configured-and-wrong is the bug.
@test "an empty transcriptRoots list is not a failure" {
    load_lib
    distill_run_begin
    run distill_sources_ok
    [ "$status" -eq 0 ]
}

# The candidate-list reading: transcriptRoots names the places Claude Code MIGHT
# keep transcripts, and only one is ever real. A run must not complain about the
# other one — a warning that fires every night is one nobody reads, which is the
# failure mode this whole check exists to cure.
@test "a root that is simply absent is not worth a word, if another has files" {
    REAL="$BATS_TEST_TMPDIR/real"
    mkdir -p "$REAL/proj"
    : >"$REAL/proj/a.jsonl"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg r "$REAL" \
        '{transcriptRoots:[$r, "/nope/not/here"]}')")"
    export DISTILL_CONFIG_JSON
    load_lib
    distill_run_begin
    run distill_sources_ok
    [ "$status" -eq 0 ]
    [[ "$output" != *"/nope/not/here"* ]]
}

# An unreadable config is `{}`, and `{}` makes transcriptRoots come back empty —
# which the guard above treats as the deliberate harvest-nothing. One broken file
# would otherwise disarm the input guard, the remote guard and every threshold.
@test "a config that failed to load is not the same as a config that says nothing" {
    DISTILL_CONFIG_JSON="" _DISTILL_CFG=""
    export DISTILL_CONFIG_JSON
    load_lib
    _DISTILL_CFG="{}"
    distill_run_begin
    run distill_sources_ok
    [ "$status" -eq 1 ]
    [[ "$output" == *"config"* ]]
}

@test "the reason a run had nothing to read survives into the record" {
    ROOTS="$BATS_TEST_TMPDIR/nowhere"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg r "$ROOTS" '{transcriptRoots:[$r]}')")"
    export DISTILL_CONFIG_JSON
    load_lib
    distill_run_begin
    _distill_daily_body >/dev/null 2>&1 || true
    distill_run_record failed

    run jq -r '.status, (.notes[] | .text)' "$STATE/runs.jsonl"
    [[ "$output" == *"failed"* ]]
    [[ "$output" == *"do not exist"* ]]
}

# The check belongs in the run path, never in preflight: --render rebuilds the
# memory tier from the corpus alone, and that is exactly what a replacement Mac
# does before it has ever opened Claude Code.
@test "--render still works on a machine with no transcripts at all" {
    run bash "$BIN" --render
    [ "$status" -eq 0 ]
    [ -f "$MEM/MAIN.md" ]
}

@test "--status reports what it can read, before anything has run" {
    window_setup
    a_transcript 0 >/dev/null
    run distill_status
    [[ "$output" == *"sources"* ]]
    [[ "$output" == *"1 transcript"* ]]
}

# chezdoctor is the only passive liveness signal this job has, so the input side
# has to reach it too — otherwise the next silent outage passes it green again.
@test "chezdoctor checks that there is anything to read" {
    sect="$BATS_TEST_TMPDIR/sect.sh"
    awk '/claudeDistiller/,/^fi$/' "$REPO_ROOT/scripts/bin/doctor.sh" >"$sect"
    grep -q 'distill_source_count' "$sect"
    grep -q 'distill_source_roots' "$sect"
}

# ─── Looking at it ────────────────────────────────────────────────────────────
#
# There is no human-facing report by design, so everything here is on demand and
# read-only. --runs matters most: runs.jsonl has always held 90 days and nothing
# read past the newest record, which is why "green and empty, every night, for
# weeks" was invisible until someone opened the file by hand.

# a_run ISO STATUS SEEN KEPT — one synthetic record in the run log.
a_run() {
    jq -nc --arg t "$1" --arg s "$2" --argjson seen "$3" --argjson kept "$4" \
        '{t:$t, end:$t, trigger:"launchd", status:$s,
          sessions:{seen:$seen, kept:$kept}, items:0, dur:4, cost:0}' \
        >>"$STATE/runs.jsonl"
}

@test "--runs reads back more than the newest record" {
    load_lib
    a_run "$(distill_iso_ago 2)" ok 5 2
    a_run "$(distill_iso_ago 1)" failed 0 0
    run distill_runs 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"5"* ]]
    [[ "$output" == *"failed"* ]]
}

@test "--runs N shows at most N" {
    load_lib
    a_run "$(distill_iso_ago 3)" ok 1 1
    a_run "$(distill_iso_ago 2)" ok 2 2
    a_run "$(distill_iso_ago 1)" ok 3 3
    run distill_runs 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"3/3"* ]]
    [[ "$output" != *"1/1"* ]]
}

# The exact shape of this bug: every run succeeded, not one of them read a thing.
@test "--runs says so when not one run saw a session" {
    load_lib
    a_run "$(distill_iso_ago 1)" ok 0 0
    run distill_runs 10
    [[ "$output" == *"not one of these runs"* ]]
}

@test "--runs on an empty log says so and exits 0" {
    load_lib
    run distill_runs 10
    [ "$status" -eq 0 ]
}

@test "--logs prints the tail, not the whole file" {
    load_lib
    mkdir -p "$STATE/logs"
    printf 'first\nsecond\nthird\n' >"$STATE/logs/nightly.log"
    run distill_logs 2 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"third"* ]]
    [[ "$output" != *"first"* ]]
}

@test "--logs before the first run says so and exits 0" {
    load_lib
    run distill_logs 50 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"nightly.log"* ]]
}

# Runtime-tested this would hang CI forever on a regression, and macOS ships no
# `timeout`. The guarantee is structural: -n must reach the plain tail.
@test "a dry run prints the log rather than following it" {
    fn="$BATS_TEST_TMPDIR/logs.sh"
    awk '/^distill_logs\(\) \{/,/^\}/' "$LIB" >"$fn"
    grep -q 'DRY_RUN' "$fn"
    grep -q 'tail -f' "$fn"
}

# "Past the promotion gate" and "in MAIN.md" are different sets — the byte cap
# evicts eligible entries silently, by design. Conflating the two would make
# --stats most wrong exactly where the number matters.
@test "--stats does not claim a cap-evicted entry is in MAIN" {
    DISTILL_CONFIG_JSON="$(cfg '{"mainCapBytes":700}')"
    export DISTILL_CONFIG_JSON
    _DISTILL_CFG=""
    load_lib
    items=""
    for i in 1 2 3 4 5 6 7 8 9; do
        items="$items$(item "a fairly long rule number $i that eats into the byte budget" s1),"
        items="$items$(item "a fairly long rule number $i that eats into the byte budget" s2),"
    done
    extract "$(date -u +%Y-%m-%d)" "[${items%,}]"
    distill_render_all

    eligible="$(distill_eligible | jq -s '[.[] | select(.eligible)] | length')"
    [ "$eligible" -eq 9 ]
    [ "$(_distill_main_entries)" -lt "$eligible" ]

    run distill_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"evicted"* ]]
}

@test "--stats survives an empty corpus" {
    load_lib
    run distill_stats
    [ "$status" -eq 0 ]
}

@test "the thirty-day window sees spend the seven-day one does not" {
    load_lib
    jq -nc --arg t "$(distill_iso_ago 3)" '{t:$t, usd:1.0}' >"$STATE/spend.jsonl"
    jq -nc --arg t "$(distill_iso_ago 20)" '{t:$t, usd:2.0}' >>"$STATE/spend.jsonl"
    [ "$(distill_spend_since 7 | jq '. == 1')" = "true" ]
    [ "$(distill_spend_since 30 | jq '. == 3')" = "true" ]
    # The rolling ceiling is defined over 7 days and must stay that way.
    [ "$(distill_spend_7d)" = "$(distill_spend_since 7)" ]
}

# ─── One corpus per profile ───────────────────────────────────────────────────
#
# `hits` is counted over the WHOLE corpus, so two profiles sharing a remote is
# not untidy — a work rule seen in two work sessions is promoted into a personal
# Mac's MAIN.md the moment the histories meet, and a push cannot be taken back.
# Adopting the right remote is the convenience; refusing the wrong one is the
# point. Every check downstream reports a green "corpus backed up" either way.

PERSONAL_URL="https://github.com/me/claude-memory-personal.git"
WORK_URL="https://github.com/me/claude-memory-work.git"

# profile_setup PROFILE — the engine loaded as if this Mac were that profile.
profile_setup() {
    DISTILL_PROFILE="$1"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg p "$PERSONAL_URL" --arg w "$WORK_URL" \
        '{remotes:{personal:$p, work:$w}}')")"
    export DISTILL_PROFILE DISTILL_CONFIG_JSON
    load_lib
}

origin_of() { git -C "$STATE" remote get-url origin 2>/dev/null; }

@test "a fresh state repo adopts the corpus its profile owns" {
    profile_setup work
    run distill_state_repo_init
    [ "$status" -eq 0 ]
    [ "$(origin_of)" = "$WORK_URL" ]
}

@test "the other profile picks the other corpus" {
    profile_setup personal
    distill_state_repo_init
    [ "$(origin_of)" = "$PERSONAL_URL" ]
}

@test "another profile's corpus is refused, by name" {
    profile_setup work
    git -C "$STATE" init -q
    git -C "$STATE" remote add origin "$PERSONAL_URL"
    run distill_state_repo_init
    [ "$status" -eq 1 ]
    [[ "$output" == *"personal"* ]]
    [ "$(origin_of)" = "$PERSONAL_URL" ]
}

@test "nothing is committed while the corpus points at another profile" {
    profile_setup work
    git -C "$STATE" init -q
    git -C "$STATE" remote add origin "$PERSONAL_URL"
    extract 2026-08-22 "[$(item 'a work rule' s1)]"
    run distill_commit_local "chore(distill): test"
    [ "$status" -eq 0 ]
    run git -C "$STATE" rev-list --count HEAD
    [ "$status" -ne 0 ]
}

@test "preflight refuses to run against another profile's corpus" {
    profile_setup work
    git -C "$STATE" init -q
    git -C "$STATE" remote add origin "$PERSONAL_URL"
    run distill_preflight
    [ "$status" -eq 1 ]
    [[ "$output" == *"personal"* ]]
}

@test "--status still reports when the remote is what is wrong" {
    profile_setup work
    git -C "$STATE" init -q
    git -C "$STATE" remote add origin "$PERSONAL_URL"
    run distill_status
    [ "$status" -eq 0 ]
    [[ "$output" != *"paths    unusable"* ]]
    [[ "$output" == *"personal corpus"* ]]
}

@test "the same repo written as ssh is the same repo" {
    profile_setup work
    git -C "$STATE" init -q
    git -C "$STATE" remote add origin "git@github.com:me/claude-memory-work.git"
    run distill_state_repo_init
    [ "$status" -eq 0 ]
    [ "$(origin_of)" = "git@github.com:me/claude-memory-work.git" ]
}

@test "spellings GitHub treats as one repo compare as one repo" {
    profile_setup work
    a="$(distill_remote_id "https://github.com/Me/Claude-Memory-Work.git")"
    [ "$a" = "github.com/me/claude-memory-work" ]
    [ "$(distill_remote_id "git@github.com:me/claude-memory-work")" = "$a" ]
    [ "$(distill_remote_id "ssh://git@github.com/me/claude-memory-work.git")" = "$a" ]
    [ "$(distill_remote_id "https://github.com/me/claude-memory-work/")" = "$a" ]
    [ "$(distill_remote_id "https://github.com/me/claude-memory-personal")" != "$a" ]
}

@test "a remote that is nobody else's profile is left alone, not overwritten" {
    profile_setup work
    git -C "$STATE" init -q
    git -C "$STATE" remote add origin "https://git.example.com/me/my-own-mirror.git"
    run distill_state_repo_init
    [ "$status" -eq 0 ]
    [ "$(origin_of)" = "https://git.example.com/me/my-own-mirror.git" ]
}

@test "with no remotes configured nothing is adopted and nothing is refused" {
    DISTILL_PROFILE=work
    export DISTILL_PROFILE
    load_lib
    run distill_state_repo_init
    [ "$status" -eq 0 ]
    [ -z "$(origin_of)" ]
}

# ─── The corpus actually reaching its remote ──────────────────────────────────
#
# Every test above this line points its remote at a URL nobody ever contacts, so
# for three years nothing exercised a push, a fetch or a restore — which is
# exactly how a backup that had never once worked kept reporting a green tick.
# These use local bare repos, so they are real git operations and still offline.
#
# Every one names its branch. `git init` follows init.defaultBranch, which is set
# on the author's Mac and unset on CI, so a test that omitted it would exercise
# `main` locally and `master` in CI.

# isolate_git — run against a git that has been configured by nobody.
#
# Not optional. This machine sets push.autoSetupRemote=true globally, which
# quietly sets the upstream that the old code never set, so three of the tests
# below passed against the very bug they exist to catch. CI sets neither that nor
# init.defaultBranch. Without this the suite would prove the fix works here and
# ship the failure to every machine configured differently.
isolate_git() {
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig-none"
    export GIT_CONFIG_SYSTEM=/dev/null
    : >"$GIT_CONFIG_GLOBAL"
}

bare_remote() {
    local b="${1:-main}" d
    isolate_git
    d="$BATS_TEST_TMPDIR/bare-$b-$RANDOM.git"
    git init -q --bare -b "$b" "$d"
    printf '%s\n' "$d"
}

# seed_remote BARE BRANCH SHARD… — a corpus that already exists, as if another
# Mac had been running for months.
seed_remote() {
    local bare="$1" branch="$2" work shard
    shift 2
    work="$BATS_TEST_TMPDIR/seed-$RANDOM"
    git clone -q -b "$branch" "$bare" "$work" 2>/dev/null || {
        git init -q -b "$branch" "$work"
        git -C "$work" remote add origin "$bare"
    }
    mkdir -p "$work/extracts"
    for shard in "$@"; do
        jq -n --argjson i "[$(item 'a remembered rule' "s-$shard")]" '{items:$i}' \
            >"$work/extracts/$shard.json"
    done
    git -C "$work" -c user.name=t -c user.email=t@t add -A
    git -C "$work" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
        commit -q -m "seed"
    git -C "$work" push -q origin "$branch"
}

attach_state() {
    local bare="$1" branch="${2:-main}"
    isolate_git
    git -C "$STATE" init -q -b "$branch"
    git -C "$STATE" remote add origin "$bare"
}

@test "the first push sets an upstream" {
    load_lib
    bare="$(bare_remote main)"
    attach_state "$bare" main
    extract 2026-08-22 "[$(item 'a rule' s1)]"
    distill_commit_local "chore(distill): test"

    [ "$(git -C "$STATE" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" = "origin/main" ]
    [ "$(git -C "$bare" rev-list --count main)" -ge 1 ]
}

@test "a corpus that already exists is restored onto a machine that has none" {
    load_lib
    bare="$(bare_remote main)"
    seed_remote "$bare" main 2026-08-01.mac-a
    attach_state "$bare" main

    distill_state_repo_init
    [ -f "$STATE/extracts/2026-08-01.mac-a.json" ]
    [ "$(git -C "$STATE" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" = "origin/main" ]
}

@test "a restored corpus keeps deriving what the other Mac wrote" {
    load_lib
    bare="$(bare_remote main)"
    seed_remote "$bare" main 2026-08-01.mac-a
    attach_state "$bare" main
    distill_state_repo_init

    run distill_derive
    [[ "$output" == *"a remembered rule"* ]]
}

@test "a remote on master is followed, not overwritten with main" {
    load_lib
    bare="$(bare_remote master)"
    seed_remote "$bare" master 2026-08-01.mac-a
    attach_state "$bare" master
    distill_state_repo_init

    [ -f "$STATE/extracts/2026-08-01.mac-a.json" ]
    [ "$(git -C "$STATE" symbolic-ref --short HEAD)" = "master" ]
}

@test "a remote that moved ahead is merged, and never left mid-rebase" {
    load_lib
    bare="$(bare_remote main)"
    attach_state "$bare" main
    extract 2026-08-22 "[$(item 'mine' s1)]"
    distill_commit_local "chore(distill): mine"

    # Another Mac pushes its own shard in the meantime.
    seed_remote "$bare" main 2026-08-23.mac-b

    extract 2026-08-24 "[$(item 'mine later' s2)]"
    distill_commit_local "chore(distill): mine later"

    [ ! -d "$STATE/.git/rebase-merge" ]
    [ ! -d "$STATE/.git/rebase-apply" ]
    # Both Macs' work is on the remote.
    run git -C "$bare" ls-tree -r --name-only main
    [[ "$output" == *"2026-08-23.mac-b.json"* ]]
    [[ "$output" == *"2026-08-24."* ]]
}

@test "an unreachable remote defers instead of wedging the repo" {
    load_lib
    attach_state "$BATS_TEST_TMPDIR/nope.git" main
    extract 2026-08-22 "[$(item 'a rule' s1)]"
    run distill_commit_local "chore(distill): test"

    [ "$status" -eq 0 ]
    [ ! -d "$STATE/.git/rebase-merge" ]
    [ "$(git -C "$STATE" rev-list --count HEAD)" -ge 1 ]
}

@test "a wedged repo is reported, and never committed onto" {
    load_lib
    bare="$(bare_remote main)"
    attach_state "$bare" main
    extract 2026-08-22 "[$(item 'a rule' s1)]"
    distill_commit_local "chore(distill): first"

    # The state the machine was found in: HEAD detached, no branch to push.
    git -C "$STATE" checkout -q --detach HEAD

    before="$(git -C "$STATE" rev-list --count HEAD)"
    extract 2026-08-23 "[$(item 'later' s2)]"
    run distill_commit_local "chore(distill): second"

    [ "$status" -eq 0 ]
    [[ "$output" == *"detached"* ]]
    [ "$(git -C "$STATE" rev-list --count HEAD)" -eq "$before" ]
}

@test "commits that never reached the remote do not read as backed up" {
    load_lib
    bare="$(bare_remote main)"
    attach_state "$bare" main
    extract 2026-08-22 "[$(item 'a rule' s1)]"
    distill_commit_local "chore(distill): test"

    # The remote goes away underneath us, exactly as a rename does.
    rm -rf "$bare"
    git -C "$STATE" commit -q --allow-empty -m "chore(distill): later"

    run distill_backup_state
    [[ "$output" == ahead* ]]

    run distill_status
    [[ "$output" != *"commit(s), pushed to"* ]]
}

@test "a corpus in step with its remote reads as backed up" {
    load_lib
    bare="$(bare_remote main)"
    attach_state "$bare" main
    extract 2026-08-22 "[$(item 'a rule' s1)]"
    distill_commit_local "chore(distill): test"

    run distill_backup_state
    [ "$output" = "synced" ]
}
