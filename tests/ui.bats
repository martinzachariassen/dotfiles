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

@test "a group where everything passed collapses to one line naming what passed" {
  record eval 'ok packages "all installed"; ok files "all linked"'
  run env DOT_ASCII=1 bash -c "source '$DOT_ROOT/lib/ui.sh'; ui_group demo 'a demo module' '$SINK'"
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  says demo 'packages - files'
}

@test "a clean group with nothing to name keeps its description" {
  record eval 'dim "an aside"'
  run ui_group demo 'a demo module' "$SINK"
  says demo 'a demo module'
}

@test "a clean group is hidden when the caller only wants what failed" {
  record eval 'ok packages "all installed"'
  DOT_UI_HIDE_CLEAN=1 run ui_group demo 'a demo module' "$SINK"
  [ -z "$output" ]
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

live() {
  export DOT_UI_RECORDS=1
  "$@" >"$SINK" 2>&1
  unset DOT_UI_RECORDS
}

@test "live group: nothing but good news is one line, carrying what was said" {
  live eval 'ok packages "3 packages"; ok files "2 links"; dim "an aside"'
  run env DOT_ASCII=1 bash -c "source '$DOT_ROOT/lib/ui.sh'; ui_live_group demo 'a demo module' <'$SINK'"
  [ "$(grep -c . <<<"$output")" -eq 1 ]
  says demo '3 packages - 2 links'
  [[ $output =~ [0-9]+\.[0-9]s$ ]]
  [[ $output != *aside* ]]
}

@test "live group: a change opens it, and what was held back comes out first" {
  live eval 'ok packages "3 packages"; info link "~/.demorc"'
  run ui_live_group demo 'a demo module' <"$SINK"
  says demo 'a demo module'
  [[ $output == *"3 packages"*"~/.demorc"* ]]
  [[ $(tail -n 1 <<<"$output") =~ 1\ change\ +[0-9]+\.[0-9]s$ ]]
}

@test "live group: a failure closes it as a problem, not as a change" {
  live eval 'info write "~/.demorc"; fail settings "could not"'
  run ui_live_group demo 'a demo module' <"$SINK"
  [[ $(tail -n 1 <<<"$output") == *"1 problem"* ]]
}

@test "live group: another program's line is shown, and opens the group" {
  live eval 'ok packages "3 packages"; echo "from somewhere else"'
  run ui_live_group demo 'a demo module' <"$SINK"
  [[ $output == *"from somewhere else"* ]]
  [[ $(tail -n 1 <<<"$output") == *done* ]]
}

@test "live group: a hook that died without a word is named by its roll-up" {
  live fold_status 'demo: apply.sh failed' false
  run ui_live_group demo 'a demo module' <"$SINK"
  [[ $output == *"demo: apply.sh failed"* ]]
}

@test "live group: a roll-up is dropped when the hook named its own problem" {
  live fold_status 'demo: apply.sh failed' bash -c "source '$DOT_ROOT/lib/dot.sh'; fail x 'the cause'; exit 1"
  run ui_live_group demo 'a demo module' <"$SINK"
  [[ $output == *"the cause"* ]]
  [[ $output != *"apply.sh failed"* ]]
}

@test "live group: each info line is tallied for the summary" {
  live eval 'info install "cask widget"; info link "~/.a"; info write "~/.b"'
  __UI_TALLY="$DOT_TMP/tally" run ui_live_group demo 'a demo module' <"$SINK"
  [ "$(wc -l <"$DOT_TMP/tally" | tr -d ' ')" -eq 3 ]
  grep -qx $'install\tcask' "$DOT_TMP/tally"
}

@test "live group: a frame overwrites the one before it, and the next line overwrites the last" {
  printf '%s\n' "$(record_line info install 'cask widget')" \
    "${__UI_FRAME}one" "${__UI_FRAME}two" "$(record_line ok installed 'cask widget')" >"$SINK"
  run ui_live_group demo 'a demo module' <"$SINK"
  [[ $output == *$'\033[2K'"${__UI_FRAME}one"* ]]
  [[ $output == *$'\033[F\033[2K'"${__UI_FRAME}two"* ]]
  [[ $output == *$'\033[F\033[2K'*"installed"* ]]
}

record_line() {
  DOT_UI_RECORDS=1 __ui_line "$@"
}

@test "changes: counted by kind, in one line" {
  printf 'install\tcask\ninstall\tformula\nlink\t~/.a\nrelink\t~/.b\nwrite\t~/.c\nbackup\t~/.d\nchmod\t~/.e\n' >"$DOT_TMP/tally"
  run env DOT_ASCII=1 bash -c "source '$DOT_ROOT/lib/ui.sh'; ui_changes '$DOT_TMP/tally'"
  [ "$output" = $'7\t1 cask - 1 formula - 2 links - 1 file written - 1 moved to backups - 1 chmod' ]
}

@test "changes: a run that changed nothing has no line at all" {
  : >"$DOT_TMP/tally"
  run ui_changes "$DOT_TMP/tally"
  [ -z "$output" ]
}

@test "a tab sends the rest of a message flush right" {
  run env DOT_COLUMNS=60 bash -c "source '$DOT_ROOT/lib/ui.sh'; ok demo \$'left\tright'"
  [ "${#output}" -eq 60 ]
  [[ $output == *right ]]
}

@test "a message too long for its note is cut, never wrapped" {
  run env DOT_COLUMNS=40 DOT_ASCII=1 bash -c \
    "source '$DOT_ROOT/lib/ui.sh'; ok demo \"\$(printf 'x%.0s' {1..80})\"\$'\t1.0s'"
  [ "${#output}" -eq 40 ]
  [[ $output == *'...  1.0s' ]]
}

@test "progress: a known size draws a bar, a percentage and what is left" {
  run env DOT_COLUMNS=80 DOT_PROGRESS=1 DOT_ASCII=1 NO_COLOR=1 bash -c \
    "source '$DOT_ROOT/lib/ui.sh'; ui_progress widget 50000000 200000000 10000000 3000000 0"
  [[ $output == "$__UI_FRAME"* ]]
  [[ $output == *'#'*'-'* ]]
  [[ $output == *' 25%  50/200 MB  10 MB/s  ~15s'* ]]
  [ "$(printf '%s' "${output#"$__UI_FRAME"}" | wc -c | tr -d ' ')" -lt 80 ]
}

@test "progress: an unknown size counts bytes instead of guessing a bar" {
  run env DOT_PROGRESS=1 DOT_ASCII=1 NO_COLOR=1 bash -c \
    "source '$DOT_ROOT/lib/ui.sh'; ui_progress jq 3500000 0 1000000 4000000 0"
  [[ $output == *'downloading  3.5 MB - 1.0 MB/s - 0:04'* ]]
}

@test "progress: nothing downloading is an install, with its clock" {
  run env DOT_PROGRESS=1 DOT_ASCII=1 NO_COLOR=1 bash -c \
    "source '$DOT_ROOT/lib/ui.sh'; ui_progress jq 0 0 0 75000000 0"
  [[ $output == *'installing  1:15'* ]]
}

@test "progress: with no terminal there is no frame at all" {
  run env DOT_PROGRESS=0 bash -c "source '$DOT_ROOT/lib/ui.sh'; ui_progress jq 0 0 0 0 0"
  [ -z "$output" ]
}

@test "the transcript drops frames and keeps the line that replaced them" {
  local log="$DOT_TMP/log"
  printf '%s\n' "${__UI_FRAME}50%" $'\033[F\033[2K\033[32mdone\033[0m' plain |
    sed -l -e "$__UI_FRAME_SED" -e h -e "$__UI_STRIP_SGR" -e "w $log" -e g >"$DOT_TMP/screen"
  [ "$(cat "$log")" = $'done\nplain' ]
  [ "$(grep -c . "$DOT_TMP/screen")" -eq 3 ]
}

@test "duration: tenths under a minute, minutes over it" {
  [ "$(ui_duration 700000)" = "0.7s" ]
  [ "$(ui_duration 41700000)" = "41.7s" ]
  [ "$(ui_duration 62000000)" = "1m02s" ]
}

@test "megabytes: one decimal under ten, none above" {
  [ "$(ui_megabytes 3456789)" = "3.4 MB" ]
  [ "$(ui_megabytes 234424393)" = "234 MB" ]
}
