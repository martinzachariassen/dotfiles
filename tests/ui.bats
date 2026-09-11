#!/usr/bin/env bats
#
# lib/ui.sh: the label column, the two alphabets, and the collapse that lets a
# report of forty green lines be read at a glance.

setup() {
  load helper
  setup_sandbox
  SINK="$DOT_TMP/sink"
}

teardown() { teardown_sandbox; }

# Records, the way a driver collects them: the printers write to a file and
# ui_group reads it back.
record() {
  export DOT_UI_RECORDS=1
  "$@" >"$SINK" 2>&1
  unset DOT_UI_RECORDS
}

# --- The column -------------------------------------------------------------

@test "the label column is the same width whoever wrote the line" {
  run bash -c "source '$DOT_ROOT/lib/ui.sh'; ok a 'one'; ok longerlabel 'two'"
  local first second
  first=$(printf '%s\n' "$output" | sed -n '1s/.*\(one\)/\1/p')
  second=$(printf '%s\n' "$output" | head -1 | grep -bo 'one' | cut -d: -f1)
  # The message of a short label starts where a padded column would put it,
  # never where the caller happened to type it.
  [ "$second" -ge 12 ]
  [ -n "$first" ]
}

@test "one argument is a message, two are a label and a message" {
  run bash -c "source '$DOT_ROOT/lib/ui.sh'; ok 'just a message'; ok label 'with a label'"
  says label 'with a label'
  [[ $output == *'just a message'* ]]
}

# --- Colour and alphabet ----------------------------------------------------

@test "NO_COLOR leaves no escape sequence behind" {
  run env NO_COLOR=1 bash -c "source '$DOT_ROOT/lib/ui.sh'; ok a b; fail c d; heading 'Title'"
  [[ $output != *$'\033'* ]]
}

@test "DOT_COLOR=1 turns colour on even with no terminal attached" {
  # The branch the transcript depends on: stdout is a pipe by the time apply
  # prints anything, and colour still has to reach the terminal.
  run env DOT_COLOR=1 bash -c "source '$DOT_ROOT/lib/ui.sh'; ok a b"
  [[ $output == *$'\033'* ]]
}

@test "a locale that is not UTF-8 falls back to an alphabet it can render" {
  run env -u LC_ALL -u LC_CTYPE LANG=C bash -c "source '$DOT_ROOT/lib/ui.sh'; ok a b"
  [[ $output != *'✓'* ]]
  [[ $output == *'+'* ]]
}

@test "DOT_ASCII is the same fallback, asked for outright" {
  run env DOT_ASCII=1 LANG=en_US.UTF-8 bash -c "source '$DOT_ROOT/lib/ui.sh'; fail a b"
  [[ $output != *'✗'* ]]
}

@test "a narrow terminal does not widen the rule past it" {
  run env DOT_COLUMNS=40 NO_COLOR=1 bash -c "source '$DOT_ROOT/lib/ui.sh'; heading 'Title'"
  # Measured in characters, not bytes: the rule is drawn with a three-byte glyph.
  local line longest=0
  while IFS= read -r line; do
    if ((${#line} > longest)); then longest=${#line}; fi
  done <<<"$output"
  [ "$longest" -le 40 ]
}

# --- Groups -----------------------------------------------------------------

@test "a group where everything passed collapses to one line" {
  record eval 'ok packages "all installed"; ok files "all linked"'
  run ui_group demo 'a demo module' "$SINK"
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  says demo 'a demo module'
}

@test "a group with a problem expands, and drops the checks that passed" {
  record eval 'ok packages "all installed"; fail files "not linked -- run: dot apply"'
  run ui_group demo 'a demo module' "$SINK"
  says files 'not linked -- run: dot apply'
  [[ $output != *'all installed'* ]]
}

@test "DOT_VERBOSE expands a healthy group again" {
  record eval 'ok packages "all installed"'
  DOT_VERBOSE=1 run ui_group demo 'a demo module' "$SINK"
  says packages 'all installed'
}

@test "output from another program is never hidden by the collapse" {
  # brew, defaults, a bare echo in a hook: nothing that did not report itself
  # healthy may disappear into a green line.
  record eval 'ok packages "all installed"; echo "a line from somewhere else"'
  run ui_group demo 'a demo module' "$SINK"
  [[ $output == *'a line from somewhere else'* ]]
}

@test "a warning colours the group without making it a failure" {
  record eval 'warn colima "not running"'
  run ui_group demo 'a demo module' "$SINK"
  says colima 'not running'
}

@test "a hook's own records reach the driver, not just its exit status" {
  # The whole reason for the record protocol: before it, three problems in one
  # hook came back as a single rolled-up failure and could not be counted.
  local hook="$DOT_TMP/doctor.sh"
  cat >"$hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
fail one 'first'
fail two 'second'
EOF
  record bash "$hook" || true
  ui_group demo 'a demo module' "$SINK"
  [ "${#DOT_PROBLEMS[@]}" -eq 2 ]
}

# --- The verdict ------------------------------------------------------------

@test "the count in the verdict is the count of the lines above it" {
  record eval 'fail a "first"; fail b "second"'
  ui_group demo 'a demo module' "$SINK"
  DOT_FAILURES=2
  run ui_verdict 'All good.' module
  [[ $output == *'2 problems'* ]]
  [[ $output != *'All good.'* ]]
}

@test "a clean run says so and repeats nothing" {
  run ui_verdict 'All good.' module
  [[ $output == *'All good.'* ]]
  [[ $output != *problem* ]]
}

@test "one problem is singular" {
  DOT_FAILURES=1
  run ui_verdict 'All good.' module
  [[ $output == *'1 problem'* ]]
  [[ $output != *'1 problems'* ]]
}
