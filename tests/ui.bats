#!/usr/bin/env bats

setup() {
  load helper
  setup_sandbox
  SINK="$DOT_TMP/sink"
}

teardown() { teardown_sandbox; }

record() {
  export DOT_UI_RECORDS=1
  "$@" >"$SINK" 2>&1
  unset DOT_UI_RECORDS
}

@test "the label column is the same width whoever wrote the line" {
  run env NO_COLOR=1 DOT_ASCII=1 bash -c \
    "source '$DOT_ROOT/lib/ui.sh'; ok a 'one'; ok longerlabel 'two'"
  local first second
  first=$(sed -n '1p' <<<"$output" | grep -bo 'one' | cut -d: -f1)
  second=$(sed -n '2p' <<<"$output" | grep -bo 'two' | cut -d: -f1)

  [ -n "$first" ]
  [ -n "$second" ]
  [ "$first" -eq "$second" ]
  [ "$first" -ge 12 ]
}

@test "one argument is a message, two are a label and a message" {
  run bash -c "source '$DOT_ROOT/lib/ui.sh'; ok 'just a message'; ok label 'with a label'"
  says label 'with a label'
  [[ $output == *'just a message'* ]]
}

@test "NO_COLOR leaves no escape sequence behind" {
  run env NO_COLOR=1 bash -c "source '$DOT_ROOT/lib/ui.sh'; ok a b; fail c d; heading 'Title'"
  [[ $output != *$'\033'* ]]
}

@test "DOT_COLOR=1 turns colour on even with no terminal attached" {
  run env DOT_COLOR=1 bash -c "source '$DOT_ROOT/lib/ui.sh'; ok a b"
  [[ $output == *$'\033'* ]]
}

@test "colour: every line closes what it opened" {
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
    opens=$(grep -o $'\033\[[0-9;]*m' <<<"$line" | grep -v $'\033\[0m' | wc -l | tr -d ' ')
    resets=$(grep -o $'\033\[0m' <<<"$line" | wc -l | tr -d ' ')
    [ "$opens" -eq "$resets" ] || {
      echo "unbalanced: $opens opened, $resets closed"
      printf '%s\n' "$line" | cat -v
      return 1
    }
  done <<<"$output"

  [ "$coloured" -ge 6 ]
}

@test "colour: each severity gets its own code, and they stay distinct" {
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
  local line longest=0
  while IFS= read -r line; do
    if ((${#line} > longest)); then longest=${#line}; fi
  done <<<"$output"
  [ "$longest" -le 40 ]
}

@test "a step carries its counter, and drops it when there is not one" {
  run bash -c "source '$DOT_ROOT/lib/ui.sh'; step 3 9 containers 'Docker via colima'"
  [[ $output == *"[3/9]"* ]]
  [[ $output == *containers* ]]
  [[ $output == *"Docker via colima"* ]]

  run bash -c "source '$DOT_ROOT/lib/ui.sh'; step '' '' core 'the repo itself'"
  [[ $output != *"["* ]]
  [[ $output == *core* ]]
}

@test "the indent reaches a hook, which is a separate process" {
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

@test "a count of one is singular, everywhere it is said" {
  [ "$(ui_count 1 module)" = "1 module" ]
  [ "$(ui_count 0 module)" = "0 modules" ]
  [ "$(ui_count 2 module)" = "2 modules" ]
}

@test "the verdict blames modules only when every finding came from one" {
  record eval 'ok packages "all installed"'
  ui_group demo 'a demo module' "$SINK"
  DOT_WARNINGS=1

  run ui_verdict 'All good.' module
  [[ $output == *'1 warning'* ]]
  [[ $output != *' of 1 module'* ]]
}

@test "the verdict's group total is singular too" {
  record eval 'fail files "not linked"'
  ui_group demo 'a demo module' "$SINK"
  run ui_verdict 'All good.' module
  [[ $output == *"of 1 module"* ]]
  [[ $output != *"of 1 modules"* ]]
}

@test "a finding is not labelled with the name of its own group" {
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

@test "elapsed: formats under and over a minute" {
  run bash -c "source '$DOT_ROOT/lib/ui.sh'; ui_elapsed 45"
  [ "$output" = 45s ]
  run bash -c "source '$DOT_ROOT/lib/ui.sh'; ui_elapsed 200"
  [ "$output" = 3m20s ]
}

@test "quoted output: a silent child gets a heartbeat before its first line" {
  run env DOT_UI_HEARTBEAT=1 bash -c \
    "source '$DOT_ROOT/lib/ui.sh'; { sleep 1.2; printf 'done\n'; } | ui_quote"
  [[ $output == *'still running'* ]]
  [[ $output == *'done'* ]]
}

@test "quoted output: a child that keeps talking gets no heartbeat" {
  run env DOT_UI_HEARTBEAT=5 bash -c \
    "source '$DOT_ROOT/lib/ui.sh'; printf 'a\nb\nc\n' | ui_quote"
  [[ $output != *'still running'* ]]
}

@test "quoted output: a line split by a heartbeat prints whole, not truncated" {
  run env DOT_UI_HEARTBEAT=1 bash -c \
    "source '$DOT_ROOT/lib/ui.sh'; { printf 'slow-'; sleep 1.2; printf 'line\n'; } | ui_quote"
  [[ $output == *'slow-line'* ]]
}

@test "quoted output: a blank line from the child is not dropped" {
  run bash -c "source '$DOT_ROOT/lib/ui.sh'; printf 'a\n\nb\n' | ui_quote"
  [ "$(wc -l <<<"$output" | tr -d ' ')" -eq 3 ]
}

@test "die prints a leftover argument rather than dropping it" {
  run bash -c "source '$DOT_ROOT/lib/ui.sh'; die 'went wrong' next 'do this' 'and this'"
  [ "$status" -eq 1 ]
  [[ $output == *'do this'* ]]
  [[ $output == *'and this'* ]]
}
