#!/usr/bin/env bats
#
# modules/claude-code/home/.claude/statusline.sh -- Claude Code pipes a JSON
# record in and shows whatever comes out. A parse slip does not error: the bar
# just renders blank or shifts every field one slot, so the output is asserted
# field by field.

load helper

setup() {
  setup_sandbox
  SCRIPT="$DOT_ROOT/modules/claude-code/home/.claude/statusline.sh"
  WORK="$DOT_TMP/work/myproject"
  mkdir -p "$WORK"
}

teardown() { teardown_sandbox; }

# ANSI colour and OSC 8 links stripped, so the assertions read the text.
render() {
  run env TMPDIR="$DOT_TMP" "$BASH" -c \
    '"$1" <<<"$2" | sed -E $'"'"'s/\x1b\\[[0-9;]*m//g; s/\x1b\\]8;;[^\x1b]*\x1b\\\\//g'"'" \
    _ "$SCRIPT" "$1"
}

@test "statusline: both lines carry every field of a full record" {
  render "$(jq -nc --arg dir "$WORK" '{
    model: {display_name: "Opus"},
    workspace: {current_dir: $dir},
    session_id: "s1", session_name: "fix bug",
    effort: {level: "medium"},
    context_window: {used_percentage: 42.7, total_input_tokens: 84000,
                     context_window_size: 200000},
    cost: {total_lines_added: 12, total_lines_removed: 3},
    pr: {number: 7, url: "https://example.com/pr/7", review_state: "approved"},
    rate_limits: {five_hour: {used_percentage: 15, resets_at: (now + 7200)},
                  seven_day: {used_percentage: 91, resets_at: (now + 90000)}}
  }')"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ ${lines[0]} == Opus\ med* ]]
  [[ ${lines[0]} == *myproject* ]]
  [[ ${lines[0]} == *"fix bug"* ]]
  [[ ${lines[0]} == *+12/-3* ]]
  [[ ${lines[0]} == *"#7"* ]]
  [[ ${lines[1]} == *" 42%"* ]]
  [[ ${lines[1]} == *84k/200k* ]]
  [[ ${lines[1]} == *5h:15%* ]]
  [[ ${lines[1]} == *7d:91%* ]]
}

@test "statusline: a record without rate_limits still renders, with no quota" {
  # API-key and Vertex sessions carry no rate_limits at all; the quota half
  # has to vanish, not print empty percentages.
  render '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":5}}'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = Sonnet ]
  [[ ${lines[1]} == *" 5%" ]]
  [[ ${lines[1]} != *5h* ]]
  [[ ${lines[1]} != *7d* ]]
}

@test "statusline: an empty record falls back rather than failing" {
  render '{}'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = '?' ]
  [[ ${lines[1]} == *" 0%" ]]
}

@test "statusline: a control character in a value cannot shift the fields" {
  # Fields are joined on \037; one smuggled in through a value would move
  # every later field one slot to the right.
  render "$(jq -nc '{model: {display_name: "A\u001fB"}, session_name: "x\ny",
    context_window: {used_percentage: 33}}')"
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == "A B"* ]]
  [[ ${lines[1]} == *" 33%"* ]]
}
