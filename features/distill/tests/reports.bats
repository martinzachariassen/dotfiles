#!/usr/bin/env bats
# The read-only answers, and undo. There is no human-facing output by design, so
# everything here is on demand, free, and writes nothing — except --undo, which
# reverts the corpus and re-renders rather than reverting the derived files.
#
# Harness in core/testing/distill.bash; engine in features/distill/lib/.

setup() {
    load '../../../core/testing/helper'
    load '../../../core/testing/distill'
    distill_setup
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
    [[ "$output" == *"5"* ]] || return 1
    [[ "$output" == *"failed"* ]] || return 1
}

@test "--runs N shows at most N" {
    load_lib
    a_run "$(distill_iso_ago 3)" ok 1 1
    a_run "$(distill_iso_ago 2)" ok 2 2
    a_run "$(distill_iso_ago 1)" ok 3 3
    run distill_runs 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"3/3"* ]] || return 1
    [[ "$output" != *"1/1"* ]] || return 1
}

# The exact shape of this bug: every run succeeded, not one of them read a thing.
@test "--runs says so when not one run saw a session" {
    load_lib
    a_run "$(distill_iso_ago 1)" ok 0 0
    run distill_runs 10
    [[ "$output" == *"not one of these runs"* ]] || return 1
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
    [[ "$output" == *"third"* ]] || return 1
    [[ "$output" != *"first"* ]] || return 1
}

@test "--logs before the first run says so and exits 0" {
    load_lib
    run distill_logs 50 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"nightly.log"* ]] || return 1
}

# Runtime-tested this would hang CI forever on a regression, and macOS ships no
# `timeout`. The guarantee is structural: -n must reach the plain tail.
@test "a dry run prints the log rather than following it" {
    load_lib
    fn="$BATS_TEST_TMPDIR/logs.sh"
    distill_fn_body distill_logs >"$fn"
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
    [[ "$output" == *"evicted"* ]] || return 1
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
    [[ "$output" != *"logs/nightly.log"* ]] || return 1
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
