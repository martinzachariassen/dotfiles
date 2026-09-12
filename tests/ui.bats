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
  # ASCII and no colour so a byte offset IS the column: a glyph is three bytes
  # in the other alphabet, and an escape is several more that a terminal never
  # draws. Both lines carry the same prefix either way, but a number that means
  # what it says is worth the two variables.
  run env NO_COLOR=1 DOT_ASCII=1 bash -c \
    "source '$DOT_ROOT/lib/ui.sh'; ok a 'one'; ok longerlabel 'two'"
  local first second
  first=$(sed -n '1p' <<<"$output" | grep -bo 'one' | cut -d: -f1)
  second=$(sed -n '2p' <<<"$output" | grep -bo 'two' | cut -d: -f1)

  # The comparison is the test: a label three times longer may not push its own
  # message right, which is what every call site padding for itself used to do.
  [ -n "$first" ]
  [ -n "$second" ]
  [ "$first" -eq "$second" ]
  # And the column is ui.sh's, not the width the caller happened to type.
  [ "$first" -ge 12 ]
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

@test "colour: every line closes what it opened" {
  # An unclosed sequence does not stay on its own line: it bleeds into the next
  # one, and the last one bleeds into the shell prompt after the run. Nothing
  # here can see what a terminal paints, but this is the property that decides
  # whether what it paints stays inside the line.
  run env DOT_COLOR=1 bash -c "source '$DOT_ROOT/lib/ui.sh'
    ok packages 'all installed'
    fail files 'not linked'
    warn colima 'not running'
    info link '~/.zshrc'
    dim 'an aside'
    say repo '~/dotfiles'
    heading 'Modules' '9 enabled'
    step 3 9 containers 'Docker via colima'
    printf 'from another program\n' | ui_quote"

  local line opens resets coloured=0
  while IFS= read -r line; do
    [[ $line == *$'\033'* ]] || continue
    coloured=$((coloured + 1))
    # `wc -l`, not `grep -c`: -c counts matching LINES, and every sequence here
    # is on the same one.
    opens=$(grep -o $'\033\[[0-9;]*m' <<<"$line" | grep -v $'\033\[0m' | wc -l | tr -d ' ')
    resets=$(grep -o $'\033\[0m' <<<"$line" | wc -l | tr -d ' ')
    [ "$opens" -eq "$resets" ] || {
      echo "unbalanced: $opens opened, $resets closed"
      printf '%s\n' "$line" | cat -v
      return 1
    }
  done <<<"$output"

  # A test that found no colour at all would pass for the wrong reason.
  [ "$coloured" -ge 6 ]
}

@test "colour: each severity gets its own code, and they stay distinct" {
  # Green for ok and red for fail is not a detail: it is the whole reason the
  # eye finds the three red lines among forty.
  run env DOT_COLOR=1 bash -c "source '$DOT_ROOT/lib/ui.sh'; ok a b"
  [[ $output == *$'\033[32m'* ]]
  run env DOT_COLOR=1 bash -c "source '$DOT_ROOT/lib/ui.sh'; fail a b"
  [[ $output == *$'\033[31m'* ]]
  run env DOT_COLOR=1 bash -c "source '$DOT_ROOT/lib/ui.sh'; warn a b"
  [[ $output == *$'\033[33m'* ]]
  run env DOT_COLOR=1 bash -c "source '$DOT_ROOT/lib/ui.sh'; info a b"
  [[ $output == *$'\033[34m'* ]]
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

# --- Steps and nesting -------------------------------------------------------

@test "a step carries its counter, and drops it when there is not one" {
  run bash -c "source '$DOT_ROOT/lib/ui.sh'; step 3 9 containers 'Docker via colima'"
  [[ $output == *"[3/9]"* ]]
  [[ $output == *containers* ]]
  [[ $output == *"Docker via colima"* ]]

  # core is a phase, not one of the numbered modules.
  run bash -c "source '$DOT_ROOT/lib/ui.sh'; step '' '' core 'the repo itself'"
  [[ $output != *"["* ]]
  [[ $output == *core* ]]
}

@test "the indent reaches a hook, which is a separate process" {
  # Without the export, everything a hook printed climbed back out to the left
  # margin under the step line it belonged to. A subshell is not the test: the
  # hook is exec'd, so only the environment carries this.
  local hook="$DOT_TMP/hook.sh"
  printf '#!/usr/bin/env bash\nsource "%s/lib/ui.sh"\nok inner deep\n' \
    "$DOT_ROOT" >"$hook"
  chmod +x "$hook"

  run bash -c "source '$DOT_ROOT/lib/ui.sh'; ui_nest; ui_nest; exec '$hook'"
  [[ $output =~ ^[[:space:]]{6,} ]]
}

@test "unnesting comes back to where it started" {
  run bash -c "source '$DOT_ROOT/lib/ui.sh'
    ui_nest; ui_nest; ui_unnest; ui_unnest
    printf '[%s]\n' \"\$DOT_UI_INDENT\""
  [[ $output == *"[]"* ]]
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

@test "a hook's findings are counted one by one, not as one exit status" {
  # fold_status sees a number, and a hook with three problems exits once. The
  # tally said "1 problem" and the list underneath it said three, which is the
  # one thing the summary may not do.
  local hook="$DOT_TMP/doctor.sh"
  cat >"$hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
warn one 'first'
warn two 'second'
warn three 'third'
EOF
  record fold_status 'demo: doctor.sh reported problems' bash "$hook"
  ui_group demo 'a demo module' "$SINK"

  [ "$DOT_WARNINGS" -eq 3 ]
  [ "$DOT_FAILURES" -eq 0 ]
  [ "${#DOT_PROBLEMS[@]}" -eq 3 ]
}

@test "a roll-up survives beside a failure that is not its own" {
  # The drop used to be decided by the failure count of the WHOLE group, so a
  # package check that failed silenced the only line naming a hook that died
  # before it could print anything. Each roll-up now answers for its own child.
  local hook="$DOT_TMP/doctor.sh"
  printf '#!/usr/bin/env bash\nexit 9\n' >"$hook"
  record eval "fail packages 'colima is not installed'
    fold_status 'core checks failed' bash '$hook'"

  run ui_group core 'the repo, the shim, the config' "$SINK"
  [[ $output == *'colima is not installed'* ]]
  [[ $output == *'core checks failed'* ]]
}

@test "a roll-up is dropped when its own child named the problem" {
  local hook="$DOT_TMP/doctor.sh"
  cat >"$hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$DOT_ROOT/lib/dot.sh"
fail files 'not linked -- run: dot apply'
EOF
  record fold_status 'demo: doctor.sh reported problems' bash "$hook"
  ui_group demo 'a demo module' "$SINK"

  [ "$DOT_FAILURES" -eq 1 ]
  [ "${#DOT_PROBLEMS[@]}" -eq 1 ]
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

# --- Counting ---------------------------------------------------------------

@test "a count of one is singular, everywhere it is said" {
  # "core + 1 modules" shipped once. ui_count is the single answer to it, so
  # what is checked here is the helper rather than each of its callers.
  [ "$(ui_count 1 module)" = "1 module" ]
  [ "$(ui_count 0 module)" = "0 modules" ]
  [ "$(ui_count 2 module)" = "2 modules" ]
}

@test "the verdict blames modules only when every finding came from one" {
  # doctor prints orphan links outside every group. Counting those into "in X
  # of Y modules" produced "1 warning in 0 of 1 module", which is a summary
  # arguing with itself.
  record eval 'ok packages "all installed"'
  ui_group demo 'a demo module' "$SINK"
  DOT_WARNINGS=1

  run ui_verdict 'All good.' module
  [[ $output == *'1 warning'* ]]
  [[ $output != *' of 1 module'* ]]
}

@test "the verdict's group total is singular too" {
  # Through a real group rather than by setting the counters: the qualifier is
  # now allowed only when the repeated list accounts for every finding, so a
  # hand-set tally with nothing behind it no longer describes any run.
  record eval 'fail files "not linked"'
  ui_group demo 'a demo module' "$SINK"
  run ui_verdict 'All good.' module
  [[ $output == *"of 1 module"* ]]
  [[ $output != *"of 1 modules"* ]]
}

# --- The repeated list ------------------------------------------------------

@test "a finding is not labelled with the name of its own group" {
  # modules/zsh/doctor.sh labels its lines "zsh", and the repeat already says
  # which module it is: "zsh  zsh: ZDOTDIR is ..." said it twice.
  record eval 'warn zsh "ZDOTDIR is somewhere else"'
  ui_group zsh 'the zsh module' "$SINK"
  DOT_WARNINGS=1
  run ui_verdict 'All good.' module
  [[ $output == *'ZDOTDIR is somewhere else'* ]]
  [[ $output != *'zsh: ZDOTDIR'* ]]
}

@test "a label that is not the group's name survives" {
  record eval 'fail files "not linked"'
  ui_group zsh 'the zsh module' "$SINK"
  DOT_FAILURES=1
  run ui_verdict 'All good.' module
  [[ $output == *'files: not linked'* ]]
}

# --- Edges ------------------------------------------------------------------

@test "a heading longer than the terminal still ends in one line" {
  run env DOT_COLUMNS=40 NO_COLOR=1 bash -c \
    "source '$DOT_ROOT/lib/ui.sh'; heading 'A title already too long by itself' 'and a note'"
  [ "$status" -eq 0 ]
  [ "$(grep -c . <<<"$output")" -eq 1 ]
}

@test "quoted output keeps a last line that has no newline" {
  run bash -c "source '$DOT_ROOT/lib/ui.sh'; printf 'no trailing newline' | ui_quote"
  [[ $output == *'no trailing newline'* ]]
}

@test "die prints a leftover argument rather than dropping it" {
  run bash -c "source '$DOT_ROOT/lib/ui.sh'; die 'went wrong' next 'do this' 'and this'"
  [ "$status" -eq 1 ]
  [[ $output == *'do this'* ]]
  [[ $output == *'and this'* ]]
}
