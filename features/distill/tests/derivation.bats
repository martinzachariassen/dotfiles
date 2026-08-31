#!/usr/bin/env bats
# What earns a place in MAIN.md, and what loses it. Everything here is derived
# from the extract corpus rather than incremented, which is what makes a repeat
# run of an already-distilled day a no-op.
#
# Harness in core/testing/distill.bash; engine in features/distill/lib/.

setup() {
    load '../../../core/testing/helper'
    load '../../../core/testing/distill'
    distill_setup
}

# ─── Derivation and the promotion gate ────────────────────────────────────────

@test "hits count distinct sessions, not sightings" {
    load_lib
    extract 2026-08-22 "[$(item 'same rule' s1),$(item 'same rule' s1)]"
    run distill_derive
    [[ "$output" == *'"hits":1'* ]] || return 1
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
    [[ "$(basename "$f")" == "2026-08-22."*".json" ]] || return 1
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
    [[ "$output" == *'"hits":2'* ]] || return 1
    # The host suffix must not leak into the date the renderer sorts and ages by.
    [[ "$output" == *'"first_seen":"2026-08-22"'* ]] || return 1
    [[ "$output" == *'"last_seen":"2026-08-22"'* ]] || return 1
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
    [[ "$output" != *"runs.jsonl"* ]] || return 1
    [[ "$output" != *"spend.jsonl"* ]] || return 1
    [[ "$output" != *"cursor.json"* ]] || return 1
    # ...and the one thing that cannot be regenerated still is.
    [[ "$output" == *"extracts/"* ]] || return 1
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
    [[ "$output" != *"true"* ]] || return 1
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
    [[ "$output" == *'"hits":2'* ]] || return 1
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
    [[ "$output" == *"Pinned.md"* ]] || return 1
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
    [[ "$output" != *"cursor.json"* ]] || return 1
}

@test "the cursor is never committed — it is meaningless on another machine" {
    load_lib
    distill_cursor_write "2026-08-22T00:00:00Z"
    printf 'x\n' >"$STATE/extracts-marker"
    distill_commit_local "chore(distill): test"
    run git -C "$STATE" ls-files
    [[ "$output" != *"cursor.json"* ]] || return 1
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
