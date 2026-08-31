#!/usr/bin/env bash
# distill.bash — the shared harness for the chezdistill suites.
#
# The engine is fifteen modules and its tests are six files, all of which need
# the same thing: a scratch memory tier, a scratch state dir, and a config that
# points at both. Going through one helper is what keeps a test from silently
# falling back to the real ~/.config/claude/memory by omitting a path.
#
#   load '../../../core/testing/helper'
#   load '../../../core/testing/distill'

# distill_setup — call from setup(), after loading helper.bash.
distill_setup() {
    BIN="$REPO_ROOT/features/distill/cli.sh"
    LIB="$REPO_ROOT/features/distill/lib.sh"
    command -v jq >/dev/null || skip "jq not installed"
    command -v git >/dev/null || skip "git not installed"

    # Memory and state are real local directories in production, so they get real
    # temp directories here — and never $HOME, which holds the live ones.
    MEM="$BATS_TEST_TMPDIR/memory"
    STATE="$BATS_TEST_TMPDIR/state"
    mkdir -p "$MEM" "$STATE"

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

# Source the engine with the logging vocabulary it expects.
load_lib() {
    # shellcheck source=../core/ui.sh
    . "$REPO_ROOT/core/ui.sh"
    ui_init_logging
    ui_init_status
    # shellcheck source=../../features/distill/lib.sh
    . "$LIB"
    DISTILL_MEMORY="$MEM"
    DISTILL_STATE="$STATE"

    # No test reads the answers this Mac actually gave. DISTILL_CONFIG_JSON only
    # pins the `.distill` table; distill_scope and distill_remote_seed read
    # top-level keys, which took them straight to the real `chezmoi data` — so
    # the suite's verdict depended on whose laptop it ran on. It passed on CI,
    # where there is no config and every scope comparison is empty-vs-empty, and
    # failed on a machine that had answered the profile question, which is the
    # wrong way round for a guard whose whole job is to fire on a mismatch.
    #
    # Tests that want an identity set DISTILL_SCOPE, or override _DISTILL_DATA.
    _DISTILL_DATA='{}'
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

# distill_fn_body NAME — the function as bash actually defines it. `load_lib`
# first.
#
# A handful of assertions are about a body's *shape* rather than its behaviour:
# that one call precedes another, that a branch exists at all. They used to awk
# a `/^name() {/,/^}/` range out of the single 2,605-line engine file. With the
# engine split across fifteen modules that range has to name the right file, and
# would go stale the moment a function moved between them — so read the
# definition bash really loaded instead. It cannot disagree with what runs.
distill_fn_body() { declare -f "$1"; }
