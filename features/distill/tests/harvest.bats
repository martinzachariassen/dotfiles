#!/usr/bin/env bats
# What there is to read, how far back, and turning the whole thing on.
#
# Harness in core/testing/distill.bash; engine in features/distill/lib/.

setup() {
    load '../../../core/testing/helper'
    load '../../../core/testing/distill'
    distill_setup
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
    [[ "$output" == *"session-0.jsonl"* ]] || return 1
    [[ "$output" != *"session-6.jsonl"* ]] || return 1
}

@test "a week-old cursor reaches the week-old transcripts" {
    window_setup
    a_transcript 0 >/dev/null
    a_transcript 6 >/dev/null
    run distill_session_files "$(distill_iso_ago 7)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"session-0.jsonl"* ]] || return 1
    [[ "$output" == *"session-6.jsonl"* ]] || return 1
}

@test "an unparseable cursor falls back to a narrow window, not to everything" {
    window_setup
    a_transcript 0 >/dev/null
    a_transcript 6 >/dev/null
    run distill_session_files "not-a-timestamp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"session-0.jsonl"* ]] || return 1
    [[ "$output" != *"session-6.jsonl"* ]] || return 1
}

@test "subagent transcripts stay out however wide the window" {
    window_setup
    mkdir -p "$ROOTS/proj/subagents"
    : >"$ROOTS/proj/subagents/sub.jsonl"
    run distill_session_files "$(distill_iso_ago 30)"
    [ "$status" -eq 0 ]
    [[ "$output" != *"sub.jsonl"* ]] || return 1
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
    [[ "$output" == *"do not exist"* ]] || return 1
    [[ "$output" == *"nowhere"* ]] || return 1
}

@test "a root that exists but holds no transcripts fails the run" {
    window_setup
    distill_run_begin
    run _distill_daily_body
    [ "$status" -ne 0 ]
    [[ "$output" == *"no transcripts"* ]] || return 1
}

# The counterweight, and the more important half: a quiet night must stay quiet.
@test "zero sessions in the window is still an ok run" {
    window_setup
    a_transcript 30 >/dev/null
    distill_run_begin
    run _distill_daily_body
    [ "$status" -eq 0 ]
    [[ "$output" != *"no transcripts"* ]] || return 1
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
    [[ "$output" != *"/nope/not/here"* ]] || return 1
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
    [[ "$output" == *"config"* ]] || return 1
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
    [[ "$output" == *"failed"* ]] || return 1
    [[ "$output" == *"do not exist"* ]] || return 1
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
    [[ "$output" == *"sources"* ]] || return 1
    [[ "$output" == *"1 transcript"* ]] || return 1
}

# chez doctor is the only passive liveness signal this job has, so the input side
# has to reach it too — otherwise the next silent outage passes it green again.
@test "chez doctor checks that there is anything to read" {
    # The section is its own file now, so this reads it directly rather than
    # awk-ing a range out of a 680-line script and hoping the range still holds.
    sect="$REPO_ROOT/features/distill/doctor.sh"
    grep -q 'distill_source_count' "$sect"
    grep -q 'distill_source_roots' "$sect"
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
