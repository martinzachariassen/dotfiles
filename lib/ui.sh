# shellcheck shell=bash
#
# Terminal output. The only file that emits colour or glyphs, and the only one
# that decides where a column starts; tests/contract.bats holds both.

# Settled here, when the library is sourced, because that is the last moment
# stdout is still the terminal: bin/dot's transcript puts a pipe in the way.
if [[ ${DOT_COLOR:-} == 1 ]]; then
  __ui_colour=1
elif [[ ${DOT_COLOR:-} == 0 || -n ${NO_COLOR:-} || ! -t 1 ]]; then
  __ui_colour=0
else
  __ui_colour=1
fi

if ((__ui_colour)); then
  __C_RESET=$'\033[0m'
  __C_DIM=$'\033[2m'
  __C_BOLD=$'\033[1m'
  __C_RED=$'\033[31m'
  __C_GREEN=$'\033[32m'
  __C_YELLOW=$'\033[33m'
  __C_BLUE=$'\033[34m'
else
  __C_RESET='' __C_DIM='' __C_BOLD='' __C_RED='' __C_GREEN='' __C_YELLOW='' __C_BLUE=''
fi
unset __ui_colour

# For bin/dot's transcript, which runs it inside a redirect where there is no
# shell left to call a function. It lives here because what colour looks like
# is this file's knowledge, and a second spelling is the one that stops
# matching when a code is added.
__UI_STRIP_SGR="s/$(printf '\033')\[[0-9;]*m//g"

# Every glyph is one column wide in both alphabets, so the label column starts
# in the same place either way. An unset LANG is the normal case under cron.
__ui_locale=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
if [[ ${DOT_ASCII:-} == 1 ]] ||
  [[ $__ui_locale != *UTF-8* && $__ui_locale != *UTF8* && $__ui_locale != *utf8* ]]; then
  __G_OK='+' __G_FAIL='x' __G_WARN='!' __G_INFO='>' __G_STEP='*' __G_RULE='-'
else
  __G_OK='✓' __G_FAIL='✗' __G_WARN='▲' __G_INFO='→' __G_STEP='▸' __G_RULE='─'
fi
unset __ui_locale

# tput needs a terminal; under the transcript's pipe there is none. Clamped,
# because a rule drawn across a 210-column window is decoration.
if [[ -n ${DOT_COLUMNS:-} ]]; then
  __UI_COLS=$DOT_COLUMNS
elif [[ -n ${COLUMNS:-} ]]; then
  __UI_COLS=$COLUMNS
else
  __UI_COLS=$(tput cols 2>/dev/null) || __UI_COLS=80
fi
[[ $__UI_COLS =~ ^[0-9]+$ ]] || __UI_COLS=80
((__UI_COLS >= 40)) || __UI_COLS=40
((__UI_COLS <= 100)) || __UI_COLS=100

# The label column, in one place. Every caller passes a bare label and this
# pads it. The wider one is for a group's own line, whose label is a module.
__UI_LABEL_W=12
__UI_GROUP_W=14

# Exported: a module hook is its own process, and without this everything it
# printed would climb back out to the left margin.
DOT_UI_INDENT=${DOT_UI_INDENT:-}
export DOT_UI_INDENT

ui_nest() {
  DOT_UI_INDENT+='  '
  export DOT_UI_INDENT
}

ui_unnest() {
  DOT_UI_INDENT=${DOT_UI_INDENT%'  '}
  export DOT_UI_INDENT
}

DOT_FAILURES=0
DOT_WARNINGS=0

# 3, not 2: bash owns 2 for syntax errors, so a hook that never ran must not
# read as "finished with a note".
DOT_STATUS_WARN=3

# The record protocol, which is what lets a report collapse -- see
# lib/CLAUDE.md. With DOT_UI_RECORDS set the printers emit
# "<RS>sev<FS>label<FS>message" instead of a rendered line and the driver
# renders it; anything in the stream WITHOUT the marker is another program's
# output and is never hidden. `foldopen`/`foldshut` are the protocol talking to
# itself: fold_status brackets one child with them so ui_group can reconcile
# the child's exit status against the findings it recorded.
__UI_RS=$'\036'
__UI_FS=$'\037'

# ok|info|warn|fail LABEL MESSAGE  -- the label lands in the aligned column.
# ok|info|warn|fail MESSAGE        -- no label, message at the column's edge.

__ui_line() {
  local sev=$1 label=''
  shift
  if (($# > 1)); then
    label=$1
    shift
  fi

  if [[ -n ${DOT_UI_RECORDS:-} ]]; then
    printf '%s%s%s%s%s%s\n' "$__UI_RS" "$sev" "$__UI_FS" "$label" "$__UI_FS" "$*"
    return 0
  fi
  __ui_render "$sev" "$label" "$*"
}

# __ui_render SEV LABEL MESSAGE [WIDTH] -- the single place a status line takes
# shape. WIDTH is for the group lines, whose label is a module name.
__ui_render() {
  local sev=$1 label=$2 msg=$3 width=${4:-$__UI_LABEL_W} glyph colour body

  case $sev in
    ok) glyph=$__G_OK colour=$__C_GREEN ;;
    fail) glyph=$__G_FAIL colour=$__C_RED ;;
    warn) glyph=$__G_WARN colour=$__C_YELLOW ;;
    info) glyph=$__G_INFO colour=$__C_BLUE ;;
    step) glyph=$__G_STEP colour=$__C_BOLD ;;
    *) glyph=' ' colour='' ;;
  esac

  if [[ -n $label ]]; then
    printf -v body '%-*s %s' "$width" "$label" "$msg"
  else
    body=$msg
  fi

  # dim and say carry no marker -- an aside must not get the weight the caller
  # withheld -- but they leave the slot empty rather than absent, or their
  # label would sit two columns left of every other line in the block.
  if [[ $sev == dim ]]; then
    printf '%s    %s%s%s\n' "$DOT_UI_INDENT" "$__C_DIM" "$body" "$__C_RESET"
  elif [[ $sev == say ]]; then
    printf '%s    %s\n' "$DOT_UI_INDENT" "$body"
  else
    printf '%s  %s%s%s %s\n' "$DOT_UI_INDENT" "$colour" "$glyph" "$__C_RESET" "$body"
  fi
}

say() { __ui_line say "$@"; }
dim() { __ui_line dim "$@"; }
ok() { __ui_line ok "$@"; }
info() { __ui_line info "$@"; }

warn() {
  __ui_line warn "$@" >&2
  DOT_WARNINGS=$((DOT_WARNINGS + 1))
}

fail() {
  __ui_line fail "$@" >&2
  DOT_FAILURES=$((DOT_FAILURES + 1))
}

# heading TITLE [NOTE] -- a divider ruled to the terminal width, with the note
# right-aligned: "── Modules ──────────────────── 9 enabled".
heading() {
  local title=$1 note=${2:-} left right fill n

  left="$__G_RULE$__G_RULE $title "
  if [[ -n $note ]]; then right=" $note"; else right=''; fi

  n=$((__UI_COLS - ${#left} - ${#right}))
  ((n > 0)) || n=1
  printf -v fill '%*s' "$n" ''
  fill=${fill// /$__G_RULE}

  printf '\n%s%s%s%s%s%s\n' \
    "$__C_BOLD" "$left" "$__C_RESET$__C_DIM" "$fill" "$__C_RESET" "$right"
}

# step CURRENT TOTAL NAME [NOTE] -- "▸ [3/9] containers   Docker via colima".
# An empty CURRENT drops the counter, for a phase that is not a numbered one.
step() {
  local i=$1 n=$2 name=$3 note=${4:-} counter=''
  if [[ -n $i ]]; then printf -v counter '[%s/%s] ' "$i" "$n"; fi
  printf '\n%s  %s%s%s %s%s%s%s%-*s%s %s%s%s\n' \
    "$DOT_UI_INDENT" "$__C_BOLD" "$__G_STEP" "$__C_RESET" \
    "$__C_DIM" "$counter" "$__C_RESET" \
    "$__C_BOLD" "$__UI_GROUP_W" "$name" "$__C_RESET" \
    "$__C_DIM" "$note" "$__C_RESET"
}

# ui_elapsed SECONDS -- "45s", "3m20s". Pure formatting, so the heartbeat
# below is the only caller that needs a clock.
ui_elapsed() {
  local s=$1
  if ((s >= 60)); then
    printf '%dm%02ds' $((s / 60)) $((s % 60))
  else
    printf '%ds' "$s"
  fi
}

# ui_quote -- another program's output, indented and dimmed. It keeps
# streaming, because a `brew bundle` that takes two minutes has to be visible
# while it runs. The caller keeps the status: ${PIPESTATUS[0]}.
#
# The read is an `if`'s condition, never a bare statement: every caller here
# runs under `set -e`, and a bare `read -t` failing -- on a timeout as much as
# on the EOF that ends the loop -- would exit the caller instead of the loop.
#
# A timeout can fire mid-line: bash still saves what it read into the
# variable. `chunk` accumulates into `line` across timeouts instead of
# replacing it, so a line split by a heartbeat prints whole, not truncated.
ui_quote() {
  local line='' chunk status idle=0 beat=${DOT_UI_HEARTBEAT:-15}
  while true; do
    chunk=''
    if IFS= read -r -t "$beat" chunk; then status=0; else status=$?; fi
    line+=$chunk
    if ((status > 128)); then
      idle=$((idle + beat))
      dim "no output for $(ui_elapsed "$idle") -- still running"
      continue
    fi
    idle=0
    if ((status == 0)) || [[ -n $line ]]; then
      printf '%s      %s%s%s\n' "$DOT_UI_INDENT" "$__C_DIM" "$line" "$__C_RESET"
    fi
    line=''
    ((status == 0)) || break
  done
}

# Filled by ui_group so the run can end by repeating its problems instead of
# telling the reader to scroll up.
DOT_PROBLEMS=()
DOT_GROUPS_CLEAN=0
DOT_GROUPS_TOTAL=0

# ui_group NAME NOTE FILE -- render the captured stream in FILE as one group,
# collapsed to a single line when every record in it is ok, and reconcile the
# tallies with what the stream says.
#
# The reconciliation is here because nowhere else can see both halves. A fold
# scope (fold_status's two markers, around one child) is read as: every finding
# inside it is added here, and the one fold_status counted for the exit status
# is taken back whenever the child named the problem itself. Records outside
# every fold scope were printed by THIS shell, which counted them already.
ui_group() {
  local name=$1 note=$2 file=$3
  local line sev label msg rest entry counted raw=0
  local -a detail=()
  local worst='ok'
  local in_fold=0 fold_fail=0 fold_warn=0 add_fail=0 add_warn=0

  while IFS= read -r line; do
    if [[ $line != "$__UI_RS"* ]]; then
      # Not ours: another program's output. It never reported itself healthy,
      # so it also keeps the group from collapsing over it.
      if [[ -n $line ]]; then
        detail+=("raw$__UI_FS$__UI_FS$line")
        raw=1
      fi
      continue
    fi
    rest=${line#"$__UI_RS"}
    sev=${rest%%"$__UI_FS"*}
    rest=${rest#*"$__UI_FS"}

    # Flat by assumption: fold_status is a driver's call, and the hooks it runs
    # do not run hooks of their own. The day one needs to, this needs a stack.
    case $sev in
      foldopen)
        in_fold=1 fold_fail=0 fold_warn=0
        continue
        ;;
      foldshut)
        counted=${rest%%"$__UI_FS"*}
        msg=${rest#*"$__UI_FS"}
        case $counted in
          fail)
            # Only THIS child's records may cancel the roll-up. A failure
            # recorded elsewhere in the group explains nothing about this one,
            # and dropping the roll-up over it loses the only line naming a
            # hook that died before it could print anything.
            if ((fold_fail > 0)); then
              DOT_FAILURES=$((DOT_FAILURES - 1))
            else
              detail+=("fail$__UI_FS$__UI_FS$msg")
            fi
            ;;
          warn)
            if ((fold_fail + fold_warn > 0)); then
              DOT_WARNINGS=$((DOT_WARNINGS - 1))
            else
              detail+=("warn$__UI_FS$__UI_FS$msg")
            fi
            ;;
        esac
        add_fail=$((add_fail + fold_fail))
        add_warn=$((add_warn + fold_warn))
        in_fold=0 fold_fail=0 fold_warn=0
        continue
        ;;
    esac

    detail+=("$sev$__UI_FS$rest")
    if ((in_fold)); then
      case $sev in
        fail) fold_fail=$((fold_fail + 1)) ;;
        warn) fold_warn=$((fold_warn + 1)) ;;
      esac
    fi
  done <"$file"

  DOT_FAILURES=$((DOT_FAILURES + add_fail))
  DOT_WARNINGS=$((DOT_WARNINGS + add_warn))

  for entry in ${detail[@]+"${detail[@]}"}; do
    sev=${entry%%"$__UI_FS"*}
    rest=${entry#*"$__UI_FS"}
    label=${rest%%"$__UI_FS"*}
    msg=${rest#*"$__UI_FS"}

    # The repeated line already carries the group's name, so a label that IS
    # that name would say it twice ("zsh  zsh: ZDOTDIR is ...").
    if [[ $label == "$name" ]]; then label=''; fi

    case $sev in
      fail)
        worst='fail'
        DOT_PROBLEMS+=("fail$__UI_FS$name$__UI_FS${label:+$label: }$msg")
        ;;
      warn)
        [[ $worst == fail ]] || worst='warn'
        DOT_PROBLEMS+=("warn$__UI_FS$name$__UI_FS${label:+$label: }$msg")
        ;;
    esac
  done

  DOT_GROUPS_TOTAL=$((DOT_GROUPS_TOTAL + 1))
  if [[ $worst == ok ]]; then DOT_GROUPS_CLEAN=$((DOT_GROUPS_CLEAN + 1)); fi

  __ui_render "$worst" "$name" "$note" "$__UI_GROUP_W"
  if [[ $worst != ok ]] || ((raw)) || [[ -n ${DOT_VERBOSE:-} ]]; then
    __ui_detail ${detail[@]+"${detail[@]}"}
  fi
}

# Only the lines that earned the space: a check that passed inside a module
# that did not is noise unless asked for.
__ui_detail() {
  local entry sev label msg
  ui_nest
  ui_nest
  for entry in "$@"; do
    sev=${entry%%"$__UI_FS"*}
    entry=${entry#*"$__UI_FS"}
    label=${entry%%"$__UI_FS"*}
    msg=${entry#*"$__UI_FS"}

    if [[ $sev == ok && -z ${DOT_VERBOSE:-} ]]; then
      continue
    fi
    if [[ $sev == raw ]]; then
      __ui_render dim '' "$msg"
    else
      __ui_render "$sev" "$label" "$msg"
    fi
  done
  ui_unnest
  ui_unnest
}

# ui_problems -- what the groups found, repeated under the verdict. Failures
# first, and capped: a list long enough to scroll is the thing this exists to
# replace. The cap is on the repeat only; every line is still up there in full.
__UI_PROBLEM_CAP=10

ui_problems() {
  local entry sev group msg want n=0 hidden=0
  ((${#DOT_PROBLEMS[@]})) || return 0

  ui_nest
  ui_nest
  for want in fail warn; do
    for entry in "${DOT_PROBLEMS[@]}"; do
      sev=${entry%%"$__UI_FS"*}
      [[ $sev == "$want" ]] || continue
      entry=${entry#*"$__UI_FS"}
      group=${entry%%"$__UI_FS"*}
      msg=${entry#*"$__UI_FS"}
      if ((n >= __UI_PROBLEM_CAP)) && [[ -z ${DOT_VERBOSE:-} ]]; then
        hidden=$((hidden + 1))
        continue
      fi
      n=$((n + 1))
      __ui_render "$sev" "$group" "$msg" "$__UI_GROUP_W"
    done
  done
  if ((hidden > 0)); then
    __ui_render dim '' "and $hidden more above -- all of them: dot doctor --verbose"
  fi
  ui_unnest
  ui_unnest
}

# ui_count N NOUN -- "1 module", "9 modules". Every count in the output goes
# through it, so "core + 1 modules" cannot come back.
ui_count() {
  if (($1 == 1)); then printf '%s %s' "$1" "$2"; else printf '%s %ss' "$1" "$2"; fi
}

# ui_verdict GOOD-NEWS -- the last line a verb prints, and the problems it
# refers to, repeated. The tallies decide the words, never the record list: a
# summary that contradicts the lines above it is the one thing this may not do.
ui_verdict() {
  local good=$1 unit=${2:-group} line=''

  if ((DOT_FAILURES > 0)); then
    line=$(ui_count "$DOT_FAILURES" problem)
    if ((DOT_WARNINGS > 0)); then line+=", $(ui_count "$DOT_WARNINGS" warning)"; fi
  elif ((DOT_WARNINGS > 0)); then
    line=$(ui_count "$DOT_WARNINGS" warning)
  fi

  # "in X of Y modules" is only true when every finding came from a group.
  # doctor prints orphan links outside all of them, and apply and remove print
  # everything outside one. DOT_PROBLEMS holds exactly the grouped findings, so
  # counting it is what proves the qualifier rather than assuming it.
  if ((DOT_GROUPS_TOTAL > 0 && DOT_FAILURES + DOT_WARNINGS > 0)) &&
    ((${#DOT_PROBLEMS[@]} == DOT_FAILURES + DOT_WARNINGS)); then
    line+=" in $((DOT_GROUPS_TOTAL - DOT_GROUPS_CLEAN)) of $(ui_count "$DOT_GROUPS_TOTAL" "$unit")"
  fi

  if ((DOT_FAILURES > 0)); then
    fail "$line"
  elif ((DOT_WARNINGS > 0)); then
    warn "$line"
  else
    ok "$good"
    return 0
  fi

  ui_problems
  if ((DOT_GROUPS_CLEAN > 0)); then
    ok "$(ui_count "$DOT_GROUPS_CLEAN" "$unit") clean"
  fi
}

# fold_status MESSAGE CMD... -- run a child process and fold its exit status
# back into the tallies. The child has already printed its own detail; MESSAGE
# only says which hook broke.
#
# Under the record protocol it brackets the child with a fold scope instead of
# printing a roll-up line, and ui_group -- which can see both the status and
# the findings -- decides what the roll-up should be. Without records there is
# nobody to reconcile with, and the status is all there is to report.
fold_status() {
  local msg=$1 status=0 counted='' records=${DOT_UI_RECORDS:-}
  shift
  if [[ -n $records ]]; then printf '%s%s\n' "$__UI_RS" foldopen >&2; fi

  "$@" || status=$?
  case $status in
    0) ;;
    "$DOT_STATUS_WARN")
      counted=warn
      DOT_WARNINGS=$((DOT_WARNINGS + 1))
      ;;
    *)
      counted=fail
      DOT_FAILURES=$((DOT_FAILURES + 1))
      ;;
  esac

  if [[ -n $records ]]; then
    printf '%s%s%s%s%s%s\n' \
      "$__UI_RS" foldshut "$__UI_FS" "$counted" "$__UI_FS" "$msg" >&2
  elif [[ $counted == fail ]]; then
    __ui_render fail '' "$msg" >&2
  fi
}

# die MESSAGE [LABEL VALUE]... -- the pairs land in the same column every other
# line uses. The last pair should say what to do next.
die() {
  local msg=$1
  shift
  __ui_render fail '' "$msg" >&2
  ui_nest
  while (($# > 1)); do
    __ui_render dim "$1" "$2" >&2
    shift 2
  done
  # An odd argument left over is a caller that meant to say something.
  if (($#)); then __ui_render dim '' "$1" >&2; fi
  ui_unnest
  exit 1
}
