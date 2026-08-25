#!/usr/bin/env bats
# chezdistill: the behaviour that bash -n and shellcheck cannot see.
#
# The cases that carry the design, and why each exists:
#   preflight    the job must NEVER create the vault — an unmounted or uncloned
#                vault would otherwise get reports written into a dead end
#   split        memory renders whether or not the vault is here, because Claude
#                @-imports MAIN.md and cannot wait for a mount
#   secrets      extracts left the vault's remote but still hold near-verbatim
#                conversation text, so the gitleaks sweep has to follow them
#   determinism  a re-render must be byte-identical, or every run makes a commit
#   promotion    hits >= minHits is what stops one misreading in one conversation
#                becoming a rule applied to every future session
#   cap          MAIN is loaded into every session forever; the limit is a
#                guarantee, not an estimate
#   spend        an unattended nightly job must not be able to bill for a week
#   undo         MAIN.md is derived, so undo reverts the ledger and re-renders

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
    jq -nc --arg v "$VAULT" --arg m "$MEM" --arg s "$STATE" \
        --argjson extra "$extra" '{
        vaultPath:$v, folder:"30-Claude", memoryPath:$m, statePath:$s,
        transcriptRoots:[],
        mainCapBytes:6144, minHits:2, demoteAfterDays:9999,
        maxSpendUsd7d:25.0, maxBudgetUsd:1.0, minTurns:3} * $extra'
}

teardown() {
    [ -n "${VAULT:-}" ] && rm -rf "$VAULT"
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
    DISTILL_VAULT="$VAULT"
    DISTILL_ROOT="$VAULT/30-Claude"
    DISTILL_VAULT_OK=1
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

# extract DATE JSON-ARRAY — the day's extract, one file per date.
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

# ─── Preflight: never create the vault, always render the memory ──────────────

@test "a missing vault exits 0 and creates nothing in its place" {
    gone="$VAULT-gone"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg g "$gone" '{vaultPath:$g}')")"
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
    [ ! -e "$VAULT/30-Claude/Daily" ]
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

# The reason the vault stopped being fatal: the persona @-imports MAIN.md, so a
# laptop with the vault unmounted must still get its memory rendered, or every
# session that day silently loses it.
@test "MAIN.md renders with no vault at all" {
    load_lib
    extract 2026-08-22 "[$(item 'survives a missing vault' s1)]"
    extract 2026-08-23 "[$(item 'survives a missing vault' s2)]"
    DISTILL_VAULT_OK=0
    DISTILL_ROOT=""
    distill_render_main
    grep -q 'survives a missing vault' "$MEM/MAIN.md"
}

@test "the memory tier is written outside the vault" {
    load_lib
    extract 2026-08-22 "[$(item 'lives in memory' s1)]"
    extract 2026-08-23 "[$(item 'lives in memory' s2)]"
    distill_render_main
    distill_render_topics
    distill_render_inbox
    [ -f "$MEM/MAIN.md" ]
    [ -f "$MEM/Topics/T.md" ]
    [ -f "$MEM/Candidates.md" ]
    [ ! -e "$VAULT/30-Claude/MAIN.md" ]
    [ ! -e "$VAULT/30-Claude/Topics" ]
    [ ! -e "$VAULT/30-Claude/.state" ]
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

# ─── Determinism and the cap ──────────────────────────────────────────────────

@test "rendering MAIN twice is byte-identical" {
    load_lib
    extract 2026-08-22 "[$(item 'rule one' s1),$(item 'rule two' s1 U)]"
    extract 2026-08-23 "[$(item 'rule one' s2),$(item 'rule two' s2 U)]"
    distill_render_main "$VAULT/first.md"
    distill_render_main "$VAULT/second.md"
    cmp "$VAULT/first.md" "$VAULT/second.md"
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

# ─── A day already distilled costs nothing to re-run ──────────────────────────

@test "sources match only once the report reflects the extract" {
    load_lib
    extract 2026-08-22 "[$(item 'x' s1)]"
    mkdir -p "$STATE/narratives"
    run distill_sources_match 2026-08-22
    [ "$status" -ne 0 ]

    distill_sources_fingerprint 2026-08-22 >"$STATE/narratives/2026-08-22.sources"
    run distill_sources_match 2026-08-22
    [ "$status" -eq 0 ]

    extract 2026-08-22 "[$(item 'x' s1),$(item 'y' s2)]"
    run distill_sources_match 2026-08-22
    [ "$status" -ne 0 ]
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

# ─── Run log ──────────────────────────────────────────────────────────────────
#
# The run log exists for the runs nobody watches: a nightly job that fires at
# 01:00 and skips everything leaves no trace anywhere the user looks, so the
# reason has to reach the vault.

@test "a run is recorded and rendered into Runs.md" {
    load_lib
    distill_run_begin daily
    DISTILL_RUN_SEEN=4
    DISTILL_RUN_KEPT=2
    DISTILL_RUN_ITEMS=7
    distill_run_record ok
    distill_render_runs

    [ -f "$STATE/runs.jsonl" ]
    grep -q '| daily | 2/4 | 7 |' "$VAULT/30-Claude/Runs.md"
}

@test "a failed run reaches the vault, with the reason" {
    load_lib
    distill_run_begin daily
    distill_fail "claude invocation failed for model sonnet" >/dev/null
    distill_run_record failed
    distill_render_runs

    grep -q '\*\*failed\*\*' "$VAULT/30-Claude/Runs.md"
    grep -q 'claude invocation failed for model sonnet' "$VAULT/30-Claude/Runs.md"
}

@test "a skipped session records why it was skipped" {
    load_lib
    distill_run_begin daily
    distill_run_session sess-1 2 "too short, no model call" 0
    distill_run_record ok
    distill_render_runs

    grep -q 'too short, no model call' "$VAULT/30-Claude/Runs.md"
}

# A night that could not write the vault could not write Runs.md either, so the
# only place the fact survives is the run record in state. Runs.md is re-rendered
# from every record, so the next run that CAN write surfaces the nights that could not.
@test "a night that skipped the vault shows up in Runs.md afterwards" {
    load_lib
    DISTILL_VAULT_OK=0
    distill_run_begin daily
    distill_run_record ok
    DISTILL_VAULT_OK=1
    distill_render_runs
    grep -q 'could not write to the vault' "$VAULT/30-Claude/Runs.md"
}

@test "records older than the retention window are pruned" {
    load_lib
    jq -nc --arg t "$(distill_iso_ago 200)" '{t:$t, end:$t}' >"$STATE/runs.jsonl"
    jq -nc --arg t "$(distill_iso_now)" '{t:$t, end:$t}' >>"$STATE/runs.jsonl"
    distill_run_prune
    [ "$(wc -l <"$STATE/runs.jsonl" | tr -d ' ')" -eq 1 ]
}

@test "rendering the run log twice is byte-identical" {
    load_lib
    distill_run_begin daily
    distill_run_record ok
    distill_render_runs "$VAULT/one.md"
    distill_render_runs "$VAULT/two.md"
    diff "$VAULT/one.md" "$VAULT/two.md"
}

@test "the run log is written before anything is committed" {
    load_lib
    # Both must happen inside distill_run_end, and the record must come first:
    # a record that lands after the commit is only ever committed a day late.
    awk '/^distill_run_end\(\) \{/,/^\}/' "$LIB" >"$VAULT/end.sh"
    [ "$(grep -n distill_run_record "$VAULT/end.sh" | cut -d: -f1)" \
        -lt "$(grep -n distill_commit_local "$VAULT/end.sh" | cut -d: -f1)" ]
}

# ─── Secrets ──────────────────────────────────────────────────────────────────
#
# The extracts left the vault's remote when state moved out, but they still hold
# near-verbatim conversation text — and MAIN.md is loaded into every session. A
# sweep that only looked at the vault would now be looking at the one directory
# with nothing sensitive in it.

@test "the secret sweep covers state and memory, not just the vault" {
    load_lib
    awk '/^distill_guard_secrets\(\) \{/,/^\}/' "$LIB" >"$VAULT/guard.sh"
    grep -q 'distill_state_dir' "$VAULT/guard.sh"
    grep -q 'distill_memory_dir' "$VAULT/guard.sh"
}

# ─── Failed writes must be loud ───────────────────────────────────────────────
#
# The 01:00 launchd run spent weeks reporting "ok, 1 warning(s)" while macOS
# refused every write into ~/Documents. Two things allowed that: `[ -w ]` passes
# under TCC because the POSIX bits are fine, and a body that returns 0 outvoted
# the failures recorded underneath it.

@test "a writable-looking but unwritable dir is caught by an actual write" {
    load_lib
    ro="$BATS_TEST_TMPDIR/ro"
    mkdir -p "$ro"
    chmod a-w "$ro"
    run distill_can_write "$ro"
    chmod u+w "$ro"
    [ "$status" -ne 0 ]
}

@test "an unwritable vault is skipped, not treated as a successful report" {
    load_lib
    chmod a-w "$VAULT/30-Claude"
    run distill_preflight
    chmod u+w "$VAULT/30-Claude"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cannot write"* ]]
}

@test "a run with any recorded failure is never reported ok" {
    load_lib
    distill_run_begin daily
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
    distill_run_begin daily
    run distill_render_main "$ro/MAIN.md"
    chmod u+w "$ro"
    [ "$status" -ne 0 ]
    grep -q 'could not write' "$_DISTILL_EVENTS"
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

@test "the cursor is never committed — it is meaningless on another machine" {
    load_lib
    distill_cursor_write "2026-08-22T00:00:00Z"
    printf 'x\n' >"$STATE/extracts-marker"
    distill_commit_local "chore(distill): test"
    run git -C "$STATE" ls-files
    [[ "$output" != *"cursor.json"* ]]
}

# ─── Undo ─────────────────────────────────────────────────────────────────────
#
# MAIN.md is derived, so undo reverts the ledger and extracts that produced it
# and renders again. Reverting the rendered file instead would leave it free to
# disagree with the ledger on the next run.

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
    : >"$SETUP_HOME/Library/LaunchAgents/no.mlz.chezdistill.nightly.plist"
    : >"$SETUP_HOME/Library/LaunchAgents/no.mlz.chezdistill.weekly.plist"

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

@test "--setup seeds MAIN.md where the persona imports it, not in the vault" {
    setup_env '["macApps"]'
    run_setup
    [ "$status" -eq 0 ]
    [ -f "$MEM/MAIN.md" ]
    [ ! -e "$VAULT/30-Claude/MAIN.md" ]
}

# The fingerprint is what keeps an already-distilled day free. Migrated in the old
# "<host>  <hash>" form it never matches, and the next run pays to re-narrate
# every day it just migrated.
@test "--setup rewrites the sources fingerprints to the new format" {
    old="$VAULT/30-Claude"
    mkdir -p "$old/.state/narratives" "$old/.state/extracts/2026-08-22"
    jq -n --argjson items "[$(item 'x' s1)]" '{items:$items}' \
        >"$old/.state/extracts/2026-08-22/$(hostname -s).json"
    printf 'some-host  abc123def456\n' >"$old/.state/narratives/2026-08-22.sources"

    setup_env '["macApps"]'
    run_setup
    [ "$status" -eq 0 ]
    [ "$(cat "$STATE/narratives/2026-08-22.sources")" = "abc123def456" ]
}

# The migration runs once and copies; nothing in the vault is deleted, because a
# half-migrated vault the user cannot inspect is worse than a duplicated one.
@test "--setup migrates an old single-folder layout without deleting it" {
    old="$VAULT/30-Claude"
    mkdir -p "$old/.state/extracts/2026-08-22" "$old/.state/ledger" "$old/Topics"
    jq -n --argjson items "[$(item 'migrated rule' s1)]" '{items:$items}' \
        >"$old/.state/extracts/2026-08-22/$(hostname -s).json"
    printf '# Pinned\n\n- pinned survives\n' >"$old/Pinned.md"

    setup_env '["macApps"]'
    run_setup
    [ "$status" -eq 0 ]
    [ -f "$STATE/extracts/2026-08-22.json" ]
    [ -f "$STATE/Pinned.md" ]
    grep -q 'migrated rule' "$STATE/extracts/2026-08-22.json"
    # Still there: the user removes the old copies by hand once a run looks right.
    [ -f "$old/Pinned.md" ]
}

@test "--setup never creates the vault itself" {
    gone="$VAULT-gone"
    DISTILL_CONFIG_JSON="$(cfg "$(jq -nc --arg g "$gone" '{vaultPath:$g}')")"
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

@test "--setup offers the apply when the plists were never rendered" {
    [ "$(uname -s)" = "Darwin" ] || skip "launchd agents are macOS-only"
    setup_env '["macApps", "claudeDistiller"]'
    rm -f "$SETUP_HOME/Library/LaunchAgents/"*.plist
    run_setup
    [ "$status" -eq 0 ]
    grep -q 'apply --force' "$STUBS/chezmoi.log"
}

@test "--setup seeds a MAIN.md even when it had to create the folder" {
    rmdir "$VAULT/30-Claude"
    setup_env '["macApps"]'
    run_setup
    [ "$status" -eq 0 ]
    [ -f "$MEM/MAIN.md" ]
    grep -q 'Generated by chezdistill' "$MEM/MAIN.md"
}
