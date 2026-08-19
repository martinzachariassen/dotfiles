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

    # Pull the Nerd Font icons straight out of the script so the codepoints live in
    # exactly one place. Asserting on a literal glyph here would mean maintaining a
    # second copy of every icon, in a file where a private-use character is invisible.
    eval "$(grep -E "^I_[A-Z_]+=\\\$'" "$STATUSLINE")"
}

teardown() {
    rm -rf "${NO_GIT_DIR:-}" "${ISO_TMP:-}"
}

# Render a payload and strip ANSI SGR + OSC 8 sequences, so assertions match the
# text a user actually reads.
render() {
    run env TMPDIR="$ISO_TMP" bash "$STATUSLINE" <<<"$1"
    [ "$status" -eq 0 ] || fail "statusline exited $status: $output"
    output="$(printf '%s' "$output" | perl -pe 's/\e\[[0-9;]*m//g; s/\e\]8;;[^\e]*\e\\//g')"
    # bats fills `lines` from the raw capture and never refreshes it, so rebuild it
    # from the stripped text. Otherwise a color escape landing mid-substring — as it
    # does between "5h " and "62%" — silently defeats every match against a line.
    lines=()
    local l
    while IFS= read -r l; do lines+=("$l"); done <<<"$output"
}

# Assertions exit rather than return: bats does not apply errexit to test bodies on
# every version, so a bare failing `[[ ]]` mid-test can be swallowed with only the
# last assertion deciding the result. Exiting fails the test at the offending line.
fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

has() {
    [[ "$output" == *"$1"* ]] || fail "expected output to contain: $1"$'\n--- actual ---\n'"$output"
}

hasnt() {
    [[ "$output" != *"$1"* ]] || fail "expected output NOT to contain: $1"$'\n--- actual ---\n'"$output"
}

# 1-indexed for readability: line 1 is identity, line 2 is budget.
line_has() {
    [[ "${lines[$(($1 - 1))]}" == *"$2"* ]] || fail "expected line $1 to contain: $2"$'\n--- actual ---\n'"${lines[$(($1 - 1))]}"
}

line_hasnt() {
    [[ "${lines[$(($1 - 1))]}" != *"$2"* ]] || fail "expected line $1 NOT to contain: $2"$'\n--- actual ---\n'"${lines[$(($1 - 1))]}"
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
        # jq evaluates now() a shade after $now was captured, and an exact 4d6h00m
        # would round down to 4d5h on that drift alone.
        rate_limits: {
            five_hour: { used_percentage: 62.4, resets_at: ($now + 6150) },
            seven_day: { used_percentage: 41.1, resets_at: ($now + 369000) }
        }
    }' | jq -c "${1:-.}"
}

# ─── structure ──────────────────────────────────────────────────────────────

@test "statusline emits exactly two lines" {
    render "$(payload)"
    [ "${#lines[@]}" -eq 2 ] || fail "expected 2 lines, got ${#lines[@]}"
}

@test "statusline survives an empty JSON object" {
    run env TMPDIR="$ISO_TMP" bash "$STATUSLINE" <<<'{}'
    [ "$status" -eq 0 ] || fail "exited $status: $output"
}

@test "statusline survives a payload with every optional field null" {
    render '{"session_id":"bats","model":{"display_name":"X"},"context_window":{"used_percentage":null},"cost":{}}'
    has "X"
}

# ─── line 1: identity and mode flags ────────────────────────────────────────

@test "line 1 shows the model, effort and directory basename" {
    render "$(payload)"
    line_has 1 "Opus 5"
    line_has 1 "MAX"
    line_has 1 "${NO_GIT_DIR##*/}"
}

@test "mode flags stay hidden while the session runs on defaults" {
    render "$(payload)"
    line_hasnt 1 "$I_BOLT"
    line_hasnt 1 "1M"
    line_hasnt 1 "off"
    line_hasnt 1 "$I_TAG"
}

@test "fast mode raises a flag" {
    render "$(payload '.fast_mode = true')"
    line_has 1 "$I_BOLT"
}

@test "crossing 200k tokens raises the premium-tier flag" {
    render "$(payload '.exceeds_200k_tokens = true')"
    line_has 1 "1M"
}

@test "disabled thinking raises a flag" {
    render "$(payload '.thinking.enabled = false')"
    line_has 1 "$I_BRAIN off"
}

@test "a renamed session is labelled" {
    render "$(payload '.session_name = "refactor-cleanup"')"
    line_has 1 "$I_TAG refactor-cleanup"
}

@test "added directories are counted" {
    render "$(payload '.workspace.added_dirs = ["/a","/b"]')"
    line_has 1 "+2dir"
}

@test "vim mode shows only outside INSERT" {
    render "$(payload '.vim.mode = "NORMAL"')"
    line_has 1 "NORMAL"
    render "$(payload '.vim.mode = "INSERT"')"
    line_hasnt 1 "INSERT"
}

@test "a non-default output style is named" {
    render "$(payload '.output_style.name = "Explanatory"')"
    line_has 1 "Explanatory"
}

@test "the diff tally lands on line 1" {
    render "$(payload)"
    line_has 1 "+120"
    line_has 1 "-34"
    line_hasnt 2 "+120"
}

@test "the diff tally still shows outside a git repo" {
    render "$(payload)"
    line_has 1 "+120"
}

@test "PR review state picks the matching marker" {
    render "$(payload '.pr = {number: 94, url: "https://example.test/94", review_state: "approved"}')"
    line_has 1 "$I_OK #94"
    render "$(payload '.pr = {number: 94, url: "https://example.test/94", review_state: "changes_requested"}')"
    line_has 1 "$I_NO #94"
    render "$(payload '.pr = {number: 94, url: "https://example.test/94", review_state: "draft"}')"
    line_has 1 "$I_PR #94 draft"
}

# ─── line 2: budget ─────────────────────────────────────────────────────────

@test "the context gauge reports a truncated percentage and compact token counts" {
    render "$(payload)"
    line_has 2 "48%"
    line_has 2 "96k/1.0M"
}

@test "cost renders with two decimals" {
    render "$(payload)"
    line_has 2 '$1.24'
}

@test "burn rate is derived from cost over wall-clock" {
    # $1.2437 over 47m ≈ $1.59/h
    render "$(payload)"
    line_has 2 '$1.59/h'
}

@test "burn rate stays hidden for the first two minutes" {
    render "$(payload '.cost.total_duration_ms = 60000')"
    line_hasnt 2 "/h"
}

@test "the clock separates API time from wall-clock" {
    render "$(payload)"
    line_has 2 "12m/47m"
}

@test "durations past an hour switch to h/m" {
    render "$(payload '.cost.total_api_duration_ms = 5400000 | .cost.total_duration_ms = 14400000')"
    line_has 2 "1h30m/4h00m"
}

@test "quota shows the used percentage next to a reset countdown" {
    render "$(payload)"
    line_has 2 "5h 62%"
    line_has 2 "$I_RESET 1h42m"
    line_has 2 "7d 41%"
    line_has 2 "$I_RESET 4d6h"
}

@test "a sub-minute reset collapses instead of ticking" {
    render "$(payload '.rate_limits.five_hour.resets_at = (now + 30)')"
    line_has 2 "$I_RESET <1m"
}

@test "an elapsed reset never renders as negative" {
    render "$(payload '.rate_limits.five_hour.resets_at = (now - 500)')"
    line_hasnt 2 "$I_RESET -"
}

@test "the quota section disappears without subscription data" {
    render "$(payload 'del(.rate_limits)')"
    line_hasnt 2 "5h "
    line_hasnt 2 "7d "
}

# ─── robustness ─────────────────────────────────────────────────────────────

@test "control characters in a string field cannot desync the field read" {
    # A newline in session_name would otherwise truncate the \037-delimited read.
    render "$(payload '.session_name = "one\ntwo"')"
    [ "${#lines[@]}" -eq 2 ] || fail "expected 2 lines, got ${#lines[@]}"
    line_has 2 '$1.24'
}

@test "an overlong text field is clipped with an ellipsis" {
    # session_name is the one unbounded string a payload fully controls, so it
    # stands in for the shared trunc helper that also bounds dir, agent and branch.
    render "$(payload '.session_name = "an extravagantly long session name that would run off any pane"')"
    line_has 1 "…"
    line_hasnt 1 "run off any pane"
}

# ─── width budget ───────────────────────────────────────────────────────────
# The payload carries no terminal width, so the budget reads COLUMNS. Segments
# shed by priority: output style, agent, session name, worktree, diff, then PR.

render_at() { # render_at <columns> <payload>
    run env TMPDIR="$ISO_TMP" COLUMNS="$1" bash "$STATUSLINE" <<<"$2"
    [ "$status" -eq 0 ] || fail "statusline exited $status: $output"
    output="$(printf '%s' "$output" | perl -pe 's/\e\[[0-9;]*m//g; s/\e\]8;;[^\e]*\e\\//g')"
    lines=()
    local l
    while IFS= read -r l; do lines+=("$l"); done <<<"$output"
}

crowded() {
    payload '.session_name = "a named session"
           | .agent = {name: "code-reviewer"}
           | .pr = {number: 1284, url: "https://example.test/1284", review_state: "open"}'
}

@test "a wide terminal keeps every segment" {
    render_at 200 "$(crowded)"
    line_has 1 "code-reviewer"
    line_has 1 "a named session"
    line_has 1 "#1284"
}

@test "a narrow terminal sheds the least important segments first" {
    render_at 60 "$(crowded)"
    line_hasnt 1 "code-reviewer"
    line_hasnt 1 "a named session"
}

@test "the essentials survive even an absurdly narrow terminal" {
    render_at 20 "$(crowded)"
    line_has 1 "Opus 5"
    line_has 1 "${NO_GIT_DIR##*/}"
    line_has 2 "48%"
    line_has 2 '$1.24'
}

@test "an unset COLUMNS drops nothing" {
    # Guards the fallback: an undetectable width must mean "unlimited", never 0 cells.
    run env TMPDIR="$ISO_TMP" COLUMNS="" bash "$STATUSLINE" <<<"$(crowded)"
    [ "$status" -eq 0 ] || fail "exited $status: $output"
    [[ "$output" == *"code-reviewer"* ]] || fail "expected no shedding, got: $output"
}

@test "every icon measures one cell so the budget arithmetic holds" {
    # The whole width model rests on this: a two-cell glyph would silently make
    # every line wider than the budget believes it is.
    local icons
    icons="$(grep -E "^I_[A-Z_]+=\\\$'" "$STATUSLINE" | sed -E "s/^I_[A-Z_]+=\\\$'(.*)'.*/\1/")"
    [ -n "$icons" ] || fail "no icons found in $STATUSLINE"
    printf '%s' "$icons" | python3 -c '
import sys, unicodedata as u
bad = [c for c in sys.stdin.read() if c != "\n"
       and u.east_asian_width(c) in ("W", "F")]
if bad:
    print("two-cell glyphs: " + " ".join(f"U+{ord(c):05X}" for c in bad))
    sys.exit(1)
' || fail "an icon is not single-width"
}

@test "a C locale produces two clean lines and no setlocale warning" {
    # CI runs without a UTF-8 locale. "UTF-8" is a valid locale name on macOS but not
    # on glibc, so naming one blindly makes bash warn on stderr and the host renders
    # the warning as a third status line.
    run env TMPDIR="$ISO_TMP" LC_ALL=C LC_CTYPE=C LANG=C bash "$STATUSLINE" <<<"$(payload)"
    [ "$status" -eq 0 ] || fail "exited $status: $output"
    [[ "$output" != *"setlocale"* ]] || fail "locale warning leaked into output: $output"
    [[ "$output" != *"warning"* ]] || fail "warning leaked into output: $output"
    [ "${#lines[@]}" -eq 2 ] || fail "expected 2 lines, got ${#lines[@]}: $output"
}

@test "a locale that cannot count characters stands the budget down" {
    # Byte-counting would make every icon read as three or four cells and shed
    # segments that fit perfectly well, so no budget is better than a wrong one.
    run env TMPDIR="$ISO_TMP" LC_ALL=C LC_CTYPE=C LANG=C COLUMNS=60 bash "$STATUSLINE" <<<"$(crowded)"
    [ "$status" -eq 0 ] || fail "exited $status: $output"
    [[ "$output" == *"code-reviewer"* ]] || fail "budget shed under a C locale: $output"
}

@test "a warm git cache renders identically to a cold one" {
    render "$(payload)"
    local cold="$output"
    render "$(payload)"
    [ "$output" = "$cold" ] || fail "warm render differs:"$'\n'"$cold"$'\n--- vs ---\n'"$output"
}

@test "a GNU-stat PATH cannot desync the cache age check" {
    # GNU stat accepts -f as --file-system and answers %m with a mount point, so the
    # mtime probe must range-check its result rather than trust the first success.
    # GNU also answers an unsupported file-system directive with "?" and exit 0.
    local stub
    stub="$(mktemp -d)"
    cat >"$stub/stat" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "-f" ]]; then echo "?"; exit 0; fi
exec /usr/bin/stat "$@"
STUB
    chmod +x "$stub/stat"

    render "$(payload)" # cold: writes the cache
    run env TMPDIR="$ISO_TMP" PATH="$stub:$PATH" bash "$STATUSLINE" <<<"$(payload)"
    rm -rf "$stub"
    [ "$status" -eq 0 ] || fail "warm render under GNU stat exited $status: $output"
    [[ "$output" != *"syntax error"* ]] || fail "arithmetic error leaked: $output"
}
