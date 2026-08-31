#!/usr/bin/env bats
# The engine's own guarantees: that it refuses to run when it cannot, that a
# failed write is loud, that nothing leaks a secret, and that -n writes nothing.
#
# Harness in core/testing/distill.bash; engine in features/distill/lib/.

setup() {
    load '../../../core/testing/helper'
    load '../../../core/testing/distill'
    distill_setup
}

# ─── Script guards ────────────────────────────────────────────────────────────

@test "hard-fails when core/ui.sh is missing" {
    tmp="$(mktemp -d)"
    cp "$BIN" "$tmp/distill.sh"
    run bash "$tmp/distill.sh"
    rm -rf "$tmp"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || return 1
    [[ "$output" == *"ui.sh"* ]] || return 1
}

@test "--help prints usage and exits 0" {
    run bash "$BIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: chezdistill"* ]] || return 1
}

@test "unknown option exits 2" {
    run bash "$BIN" --nope
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option"* ]] || return 1
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
    [[ "$output" == *"unknown option: --nope"* ]] || return 1
}

@test "a non-numeric count is refused rather than read as a flag" {
    run bash "$BIN" --runs 7d
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option: 7d"* ]] || return 1

    run bash "$BIN" --runs=abc
    [ "$status" -eq 2 ]
}

@test "-f outside --logs is refused, not ignored" {
    run bash "$BIN" --status -f
    [ "$status" -eq 2 ]
    [[ "$output" == *"only applies to --logs"* ]] || return 1
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
    [[ "$output" == *"cannot write"* ]] || return 1
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

# ─── Secrets ──────────────────────────────────────────────────────────────────
#
# The extracts hold near-verbatim conversation text, and MAIN.md is loaded into
# every session. Both destinations have to be swept, and the state repo is the
# one that can be given a remote.

@test "the secret sweep covers state and memory" {
    load_lib
    guard="$BATS_TEST_TMPDIR/guard.sh"
    distill_fn_body distill_guard_secrets >"$guard"
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
    [[ "$output" == *'"status":"failed"'* ]] || return 1
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
