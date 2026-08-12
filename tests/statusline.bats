#!/usr/bin/env bats
# Coverage for the Claude Code status line: field extraction, the conditional
# mode flags, and the number/duration formatters. The git section is exercised
# only for its "absent" path — the script reads live repo state, so asserting on
# branch names or dirty counts would make these tests depend on the worktree.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    STATUSLINE="$REPO_ROOT/src/dot_config/claude/executable_statusline.sh"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"

    # A non-repo cwd so the git block short-circuits, and a private TMPDIR so the
    # per-session git cache never collides with a real session's.
    NO_GIT_DIR="$(mktemp -d)"
    ISO_TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "${NO_GIT_DIR:-}" "${ISO_TMP:-}"
}

# Render a payload and strip ANSI SGR + OSC 8 sequences, so assertions match the
# text a user actually reads.
render() {
    run env TMPDIR="$ISO_TMP" bash "$STATUSLINE" <<<"$1"
    [ "$status" -eq 0 ]
    output="$(printf '%s' "$output" | perl -pe 's/\e\[[0-9;]*m//g; s/\e\]8;;[^\e]*\e\\//g')"
}

# A payload with every field the script reads, overridable per test via a jq filter.
payload() {
    jq -nc --arg dir "$NO_GIT_DIR" --argjson now "$(date +%s)" '{
        session_id: "bats",
        cwd: $dir,
        model: { id: "claude-opus-5", display_name: "Opus 5" },
        workspace: { current_dir: $dir, project_dir: $dir, added_dirs: [] },
        output_style: { name: "default" },
        cost: {
            total_cost_usd: 1.2437,
            total_duration_ms: 2820000,
            total_api_duration_ms: 735000,
            total_lines_added: 120,
            total_lines_removed: 34
        },
        context_window: {
            total_input_tokens: 96000,
            total_output_tokens: 900,
            context_window_size: 1000000,
            used_percentage: 48.2
        },
        effort: { level: "max" },
        thinking: { enabled: true },
        # Reset offsets sit deliberately off a unit boundary (1h42m30s, 4d6h30m):
        # jq evaluates now() a shade after $now was captured, and an exact 1h42m00s
        # would round down to 1h41m on that drift alone.
        rate_limits: {
            five_hour: { used_percentage: 62.4, resets_at: ($now + 6150) },
            seven_day: { used_percentage: 41.1, resets_at: ($now + 369000) }
        }
    }' | jq -c "${1:-.}"
}

# ─── structure ──────────────────────────────────────────────────────────────

@test "statusline emits exactly two lines" {
    render "$(payload)"
    [ "${#lines[@]}" -eq 2 ]
}

@test "statusline survives an empty JSON object" {
    run env TMPDIR="$ISO_TMP" bash "$STATUSLINE" <<<'{}'
    [ "$status" -eq 0 ]
}

@test "statusline survives a payload with every optional field null" {
    render '{"session_id":"bats","model":{"display_name":"X"},"context_window":{"used_percentage":null},"cost":{}}'
    [[ "$output" == *"X"* ]]
}

# ─── line 1: identity and mode flags ────────────────────────────────────────

@test "line 1 shows the model, effort and directory basename" {
    render "$(payload)"
    [[ "${lines[0]}" == *"Opus 5"* ]]
    [[ "${lines[0]}" == *"ᴍᴀx"* ]]
    [[ "${lines[0]}" == *"${NO_GIT_DIR##*/}"* ]]
}

@test "mode flags stay hidden while the session runs on defaults" {
    render "$(payload)"
    [[ "${lines[0]}" != *"⚡"* ]]
    [[ "${lines[0]}" != *"1M"* ]]
    [[ "${lines[0]}" != *"off"* ]]
    [[ "${lines[0]}" != *"🏷"* ]]
}

@test "fast mode raises a flag" {
    render "$(payload '.fast_mode = true')"
    [[ "${lines[0]}" == *"⚡"* ]]
}

@test "crossing 200k tokens raises the premium-tier flag" {
    render "$(payload '.exceeds_200k_tokens = true')"
    [[ "${lines[0]}" == *"1M"* ]]
}

@test "disabled thinking raises a flag" {
    render "$(payload '.thinking.enabled = false')"
    [[ "${lines[0]}" == *"🧠off"* ]]
}

@test "a renamed session is labelled" {
    render "$(payload '.session_name = "refactor-cleanup"')"
    [[ "${lines[0]}" == *"🏷 refactor-cleanup"* ]]
}

@test "added directories are counted" {
    render "$(payload '.workspace.added_dirs = ["/a","/b"]')"
    [[ "${lines[0]}" == *"+2dir"* ]]
}

@test "vim mode shows only outside INSERT" {
    render "$(payload '.vim.mode = "NORMAL"')"
    [[ "${lines[0]}" == *"NORMAL"* ]]
    render "$(payload '.vim.mode = "INSERT"')"
    [[ "${lines[0]}" != *"INSERT"* ]]
}

@test "a non-default output style is named" {
    render "$(payload '.output_style.name = "Explanatory"')"
    [[ "${lines[0]}" == *"Explanatory"* ]]
}

@test "the diff tally lands on line 1" {
    render "$(payload)"
    [[ "${lines[0]}" == *"+120"* ]]
    [[ "${lines[0]}" == *"-34"* ]]
    [[ "${lines[1]}" != *"+120"* ]]
}

@test "PR review state picks the matching marker" {
    render "$(payload '.pr = {number: 94, url: "https://example.test/94", review_state: "approved"}')"
    [[ "${lines[0]}" == *"✓ PR #94"* ]]
    render "$(payload '.pr = {number: 94, url: "https://example.test/94", review_state: "changes_requested"}')"
    [[ "${lines[0]}" == *"✗ PR #94"* ]]
    render "$(payload '.pr = {number: 94, url: "https://example.test/94", review_state: "draft"}')"
    [[ "${lines[0]}" == *"PR #94 (draft)"* ]]
}

# ─── line 2: budget ─────────────────────────────────────────────────────────

@test "the context gauge reports a truncated percentage and compact token counts" {
    render "$(payload)"
    [[ "${lines[1]}" == *"48%"* ]]
    [[ "${lines[1]}" == *"96k/1.0M"* ]]
}

@test "cost renders with two decimals" {
    render "$(payload)"
    [[ "${lines[1]}" == *'$1.24'* ]]
}

@test "burn rate is derived from cost over wall-clock" {
    # $1.2437 over 47m ≈ $1.59/h
    render "$(payload)"
    [[ "${lines[1]}" == *'$1.59/h'* ]]
}

@test "burn rate stays hidden for the first two minutes" {
    render "$(payload '.cost.total_duration_ms = 60000')"
    [[ "${lines[1]}" != *"/h"* ]]
}

@test "the clock separates API time from wall-clock" {
    render "$(payload)"
    [[ "${lines[1]}" == *"12m/47m"* ]]
}

@test "durations past an hour switch to h/m" {
    render "$(payload '.cost.total_api_duration_ms = 5400000 | .cost.total_duration_ms = 14400000')"
    [[ "${lines[1]}" == *"1h30m/4h00m"* ]]
}

@test "quota shows the used percentage next to a reset countdown" {
    render "$(payload)"
    [[ "${lines[1]}" == *"5h 62%"* ]]
    [[ "${lines[1]}" == *"↻1h42m"* ]]
    [[ "${lines[1]}" == *"7d 41%"* ]]
    [[ "${lines[1]}" == *"↻4d6h"* ]]
}

@test "a sub-minute reset collapses instead of ticking" {
    render "$(payload '.rate_limits.five_hour.resets_at = (now + 30)')"
    [[ "${lines[1]}" == *"↻<1m"* ]]
}

@test "an elapsed reset never renders as negative" {
    render "$(payload '.rate_limits.five_hour.resets_at = (now - 500)')"
    [[ "${lines[1]}" != *"↻-"* ]]
}

@test "the quota section disappears without subscription data" {
    render "$(payload 'del(.rate_limits)')"
    [[ "${lines[1]}" != *"5h "* ]]
    [[ "${lines[1]}" != *"7d "* ]]
}

# ─── robustness ─────────────────────────────────────────────────────────────

@test "control characters in a string field cannot desync the field read" {
    # A newline in session_name would otherwise truncate the \037-delimited read.
    render "$(payload '.session_name = "one\ntwo"')"
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[1]}" == *'$1.24'* ]]
}

@test "an overlong branch name is truncated" {
    grep -q 'BRANCH:0:29' "$STATUSLINE"
}

@test "a warm git cache renders identically to a cold one" {
    render "$(payload)"
    local cold="$output"
    render "$(payload)"
    [ "$output" = "$cold" ]
}

@test "a GNU-stat PATH cannot desync the cache age check" {
    # GNU stat accepts -f as --file-system and answers %m with a mount point, so the
    # mtime probe must range-check its result rather than trust the first success.
    local stub
    stub="$(mktemp -d)"
    # GNU stat answers an unsupported file-system directive with "?" and exit 0,
    # so the probe cannot lean on the exit status to detect the wrong stat flavour.
    cat >"$stub/stat" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "-f" ]]; then echo "?"; exit 0; fi
exec /usr/bin/stat "$@"
STUB
    chmod +x "$stub/stat"

    render "$(payload)" # cold: writes the cache
    run env TMPDIR="$ISO_TMP" PATH="$stub:$PATH" bash "$STATUSLINE" <<<"$(payload)"
    rm -rf "$stub"
    [ "$status" -eq 0 ]
}
