#!/usr/bin/env bats
# chezdistill: the behaviour that bash -n and shellcheck cannot see.
#
# The cases that carry the design, and why each exists:
#   preflight    the job must NEVER create the vault — an unmounted or unclonned
#                vault would otherwise get reports written into a dead end
#   determinism  two machines render MAIN.md independently; if the render is not
#                byte-stable they conflict in git on every single run
#   promotion    hits >= minHits is what stops one misreading in one conversation
#                becoming a rule applied to every future session
#   unknown      unclassified origin must never reach MAIN, so a missing pattern
#                surfaces as a visible pile instead of as silently misfiled work
#   cap          MAIN is loaded into every session forever; the limit is a
#                guarantee, not an estimate
#   spend        an unattended nightly job must not be able to bill for a week

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    BIN="$REPO_ROOT/scripts/bin/distill.sh"
    LIB="$REPO_ROOT/scripts/lib/distill.sh"
    command -v jq >/dev/null || skip "jq not installed"
    command -v git >/dev/null || skip "git not installed"

    VAULT="$(mktemp -d)"
    mkdir -p "$VAULT/.obsidian" "$VAULT/30-Claude"
    git -C "$VAULT" init -q
    git -C "$VAULT" remote add origin https://example.invalid/x.git

    export DISTILL_CONFIG_JSON
    DISTILL_CONFIG_JSON="$(jq -nc --arg v "$VAULT" '{
        vaultPath:$v, folder:"30-Claude", transcriptRoots:[],
        mainCapBytes:6144, minHits:2, demoteAfterDays:9999,
        maxSpendUsd7d:25.0, maxBudgetUsd:1.0, minTurns:3,
        workRemotes:["work.example.com"], workPaths:[],
        personalPaths:["/tmp/personal-root"]}')"
}

teardown() {
    [ -n "${VAULT:-}" ] && rm -rf "$VAULT"
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
    DISTILL_VAULT="$VAULT"
    DISTILL_ROOT="$VAULT/30-Claude"
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

# extract DATE HOST JSON-ARRAY — write one machine's extract for a day.
extract() {
    mkdir -p "$VAULT/30-Claude/.state/extracts/$1"
    jq -n --argjson items "$3" '{items:$items}' \
        >"$VAULT/30-Claude/.state/extracts/$1/$2.json"
}

item() {
    jq -nc --arg t "$1" --arg o "$2" --arg s "$3" \
        '{text:$t, detail:"detail", kind:"learnings", topic:"T",
          origin:$o, session:$s}'
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

# ─── Preflight: never create anything ─────────────────────────────────────────

@test "a missing vault exits 0 and creates nothing" {
    gone="$VAULT-gone"
    DISTILL_CONFIG_JSON="$(jq -nc --arg v "$gone" '{vaultPath:$v, folder:"30-Claude"}')"
    export DISTILL_CONFIG_JSON
    run bash "$BIN"
    [ "$status" -eq 0 ]
    [ ! -e "$gone" ]
}

@test "a directory without .obsidian is not treated as a vault" {
    rm -rf "$VAULT/.obsidian"
    run bash "$BIN"
    [ "$status" -eq 0 ]
    [[ "$output" == *".obsidian"* ]]
    [ ! -e "$VAULT/30-Claude/MAIN.md" ]
}

@test "a missing 30-Claude folder is never created" {
    rmdir "$VAULT/30-Claude"
    run bash "$BIN"
    [ "$status" -eq 0 ]
    [ ! -e "$VAULT/30-Claude" ]
}

@test "--status reports an unavailable vault without failing" {
    rmdir "$VAULT/30-Claude"
    run bash "$BIN" --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"not available"* ]]
}

# ─── Origin classification ────────────────────────────────────────────────────

@test "a work git remote wins over the path fallback" {
    load_lib
    repo="$(mktemp -d)"
    git -C "$repo" init -q
    git -C "$repo" remote add origin "https://work.example.com/team/svc.git"
    run distill_classify_origin "$repo"
    rm -rf "$repo"
    [ "$output" = "work" ]
}

@test "a personal path classifies as personal" {
    load_lib
    mkdir -p /tmp/personal-root/proj
    run distill_classify_origin /tmp/personal-root/proj
    [ "$output" = "personal" ]
}

@test "an unmatched path falls through to unknown" {
    load_lib
    run distill_classify_origin /tmp/nowhere-in-particular
    [ "$output" = "unknown" ]
}

@test "entry ids ignore case, spacing and trailing punctuation" {
    load_lib
    a="$(distill_entry_id 'Use rg, never grep.')"
    b="$(distill_entry_id '  use   RG, never grep  ')"
    [ -n "$a" ]
    [ "$a" = "$b" ]
}

# ─── Derivation and the promotion gate ────────────────────────────────────────

@test "an entry seen in both contexts becomes always" {
    load_lib
    extract 2026-08-22 hostA "[$(item 'shared rule' personal s1)]"
    extract 2026-08-23 hostB "[$(item 'shared rule' work s2)]"
    run distill_derive
    [[ "$output" == *'"scope":"always"'* ]]
}

@test "a single sighting stays out of MAIN and lands in the inbox" {
    load_lib
    extract 2026-08-22 hostA "[$(item 'seen once' personal s1)]"
    distill_render_main
    distill_render_inbox
    refute_file_contains "$VAULT/30-Claude/MAIN.md" 'seen once'
    grep -q 'seen once' "$VAULT/30-Claude/Inbox/Candidates.md"
}

@test "a second sighting promotes the entry into MAIN" {
    load_lib
    extract 2026-08-22 hostA "[$(item 'promote me' personal s1)]"
    extract 2026-08-23 hostA "[$(item 'promote me' personal s2)]"
    distill_render_main
    grep -q 'promote me' "$VAULT/30-Claude/MAIN.md"
}

@test "an unknown origin never reaches MAIN however often it is seen" {
    load_lib
    extract 2026-08-22 hostA "[$(item 'unclassified' unknown s1)]"
    extract 2026-08-23 hostA "[$(item 'unclassified' unknown s2)]"
    distill_render_main
    distill_render_inbox
    refute_file_contains "$VAULT/30-Claude/MAIN.md" 'unclassified'
    grep -q 'unclassified' "$VAULT/30-Claude/Inbox/Candidates.md"
}

# ─── Determinism and the cap ──────────────────────────────────────────────────

@test "rendering MAIN twice is byte-identical" {
    load_lib
    extract 2026-08-22 hostA "[$(item 'rule one' personal s1),$(item 'rule two' work s1)]"
    extract 2026-08-23 hostB "[$(item 'rule one' personal s2),$(item 'rule two' work s2)]"
    distill_render_main "$VAULT/first.md"
    distill_render_main "$VAULT/second.md"
    cmp "$VAULT/first.md" "$VAULT/second.md"
}

@test "the cap is a guarantee and Pinned.md survives it" {
    load_lib
    printf '# Pinned\n\n- keep me forever\n' >"$VAULT/30-Claude/Pinned.md"
    items="["
    for i in 1 2 3 4 5 6 7 8 9; do
        items="$items$(item "a fairly long rule number $i that eats into the byte budget" personal s1),"
        items="$items$(item "a fairly long rule number $i that eats into the byte budget" personal s2),"
    done
    items="${items%,}]"
    extract 2026-08-22 hostA "$items"

    DISTILL_CONFIG_JSON="$(jq -nc --arg v "$VAULT" '{
        vaultPath:$v, folder:"30-Claude", mainCapBytes:400,
        minHits:2, demoteAfterDays:9999}')"
    _DISTILL_CFG=""
    distill_render_main
    size="$(wc -c <"$VAULT/30-Claude/MAIN.md" | tr -d ' ')"
    [ "$size" -le 400 ]
    grep -q 'keep me forever' "$VAULT/30-Claude/MAIN.md"
}

# ─── The second machine must be a no-op ───────────────────────────────────────

@test "sources match only once the report reflects every extract" {
    load_lib
    extract 2026-08-22 hostA "[$(item 'x' personal s1)]"
    mkdir -p "$VAULT/30-Claude/.state/narratives"
    run distill_sources_match 2026-08-22
    [ "$status" -ne 0 ]

    distill_sources_fingerprint 2026-08-22 \
        >"$VAULT/30-Claude/.state/narratives/2026-08-22.sources"
    run distill_sources_match 2026-08-22
    [ "$status" -eq 0 ]

    extract 2026-08-22 hostB "[$(item 'y' work s2)]"
    run distill_sources_match 2026-08-22
    [ "$status" -ne 0 ]
}

# ─── Cost ─────────────────────────────────────────────────────────────────────

@test "the rolling spend ceiling refuses to start a run" {
    load_lib
    mkdir -p "$VAULT/30-Claude/.state/spend"
    printf '{"t":"%s","usd":99}\n' "$(distill_iso_now)" \
        >"$VAULT/30-Claude/.state/spend/hostA.jsonl"
    run distill_spend_ok
    [ "$status" -ne 0 ]
    [[ "$output" == *"ceiling"* ]]
}

@test "spend under the ceiling allows a run" {
    load_lib
    mkdir -p "$VAULT/30-Claude/.state/spend"
    printf '{"t":"%s","usd":0.5}\n' "$(distill_iso_now)" \
        >"$VAULT/30-Claude/.state/spend/hostA.jsonl"
    run distill_spend_ok
    [ "$status" -eq 0 ]
}

@test "spend older than seven days no longer counts" {
    load_lib
    mkdir -p "$VAULT/30-Claude/.state/spend"
    printf '{"t":"%s","usd":99}\n' "$(distill_iso_ago 30)" \
        >"$VAULT/30-Claude/.state/spend/hostA.jsonl"
    run distill_spend_ok
    [ "$status" -eq 0 ]
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

# ─── Setup ────────────────────────────────────────────────────────────────────
#
# --setup is the only path allowed to create the 30-Claude folder. The guard it
# must not weaken is the one above: a vault that is unmounted or was never cloned
# looks exactly like an empty directory, so setup has to refuse just as hard.

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

    # Both plists present by default: a missing one is itself a reason to apply,
    # which would mask what most of these tests are actually asserting.
    mkdir -p "$SETUP_HOME/Library/LaunchAgents"
    : >"$SETUP_HOME/Library/LaunchAgents/no.zachariassen.chezdistill.nightly.plist"
    : >"$SETUP_HOME/Library/LaunchAgents/no.zachariassen.chezdistill.weekly.plist"

    CHEZMOI_DATA="$(printf '%s' "$1" | jq -c '{modules: .}')"
    export CHEZMOI_DATA
}

# run_setup FLAGS… — --setup against the fake HOME, stubs first on PATH.
run_setup() {
    HOME="$SETUP_HOME" PATH="$STUBS:$PATH" YES=1 run bash "$BIN" --setup "$@"
}

@test "--setup creates the 30-Claude folder inside a real vault" {
    rmdir "$VAULT/30-Claude"
    setup_env '["macApps"]'
    run_setup
    [ "$status" -eq 0 ]
    [ -d "$VAULT/30-Claude" ]
}

@test "--setup never creates the vault itself" {
    gone="$VAULT-gone"
    DISTILL_CONFIG_JSON="$(jq -nc --arg v "$gone" '{vaultPath:$v, folder:"30-Claude"}')"
    export DISTILL_CONFIG_JSON
    setup_env '["macApps"]'
    run_setup
    [ "$status" -eq 1 ]
    [ ! -e "$gone" ]
}

@test "--setup refuses a directory that is not a vault" {
    rm -rf "$VAULT/.obsidian" "$VAULT/30-Claude"
    setup_env '["macApps"]'
    run_setup
    [ "$status" -eq 1 ]
    [[ "$output" == *".obsidian"* ]]
    [ ! -e "$VAULT/30-Claude" ]
}

@test "--setup -n creates nothing and enables nothing" {
    rmdir "$VAULT/30-Claude"
    setup_env '["macApps"]'
    run_setup -n
    [ "$status" -eq 0 ]
    [ ! -e "$VAULT/30-Claude" ]
    grep -q 'modules     = \["macApps"\]$' "$SETUP_HOME/.config/chezmoi/chezmoi.toml"
    [ ! -f "$STUBS/chezmoi.log" ]
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
    DISTILL_CONFIG_JSON="$(jq -nc --arg v "$VAULT" --arg r "$ROOTS" \
        '{vaultPath:$v, folder:"30-Claude", transcriptRoots:[$r]}')"
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

@test "--setup offers the apply when the plists were never rendered" {
    [ "$(uname -s)" = "Darwin" ] || skip "launchd agents are macOS-only"
    setup_env '["macApps", "claudeDistiller"]'
    rm -f "$SETUP_HOME/Library/LaunchAgents/"*.plist
    run_setup
    [ "$status" -eq 0 ]
    grep -q 'apply --force' "$STUBS/chezmoi.log"
}

@test "--setup seeds a MAIN.md for the persona to import" {
    rmdir "$VAULT/30-Claude"
    setup_env '["macApps"]'
    run_setup
    [ "$status" -eq 0 ]
    [ -f "$VAULT/30-Claude/MAIN.md" ]
    grep -q 'Generated by chezdistill' "$VAULT/30-Claude/MAIN.md"
}
