# shellcheck shell=bash
#
# Terminal output. The only file that emits colour or glyphs, and the only one
# that decides where a column starts; tests/contract.bats holds both.

# --- What this terminal can do ----------------------------------------------
#
# Settled here, when the library is sourced, because that is the last moment
# stdout is still the terminal: bin/dot's transcript puts a pipe in the way
# afterwards and every line would come out plain. The log stays clean from the
# other end -- __transcript_start strips colour on the way into the file.
#
# DOT_COLOR, DOT_ASCII and DOT_COLUMNS are inputs, like DOT_BREW_BIN: without
# them the branch a test needs is the one the machine running it never takes.

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

# Taking colour back out again, for bin/dot's transcript. A sed expression and
# not a function because it runs inside the redirect that makes the log, where
# there is no shell left to call one. It lives here for the same reason the
# escapes above do: what colour looks like is this file's knowledge, and a strip
# spelled somewhere else is the copy that stops matching when a code is added.
__UI_STRIP_SGR="s/$(printf '\033')\[[0-9;]*m//g"

# Every glyph is one column wide in both alphabets, so the label column starts
# in the same place whichever one is in use. A locale that does not say UTF-8
# renders ✓ as a question mark or worse, and an unset LANG is the normal case
# under cron and CI.
__ui_locale=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
if [[ ${DOT_ASCII:-} == 1 ]] ||
  [[ $__ui_locale != *UTF-8* && $__ui_locale != *UTF8* && $__ui_locale != *utf8* ]]; then
  __G_OK='+' __G_FAIL='x' __G_WARN='!' __G_INFO='>' __G_STEP='*' __G_RULE='-'
else
  __G_OK='✓' __G_FAIL='✗' __G_WARN='▲' __G_INFO='→' __G_STEP='▸' __G_RULE='─'
fi
unset __ui_locale

# tput needs a terminal; under the transcript's pipe it has none, and 80 is the
# width every other tool falls back to. Clamped, because a rule drawn across a
# 210-column window is a decoration, not a divider.
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
# pads it; a call site that pads its own is the drift this replaced. The wider
# one is for a group's own line, where the label is a module name.
__UI_LABEL_W=12
__UI_GROUP_W=14

# How far in the next line sits. Exported, because a module hook is its own
# process: without that, everything a hook printed would climb back out to the
# left margin under the step line it belongs to.
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

# `fail` never exits; lib/dot.sh's EXIT trap turns the tally into a status.
DOT_FAILURES=0
DOT_WARNINGS=0

# The exit status of a hook that only warned. 3, not 2: bash owns 2 for syntax
# errors, so a hook that never ran must not read as "finished with a note".
DOT_STATUS_WARN=3

# --- Records ----------------------------------------------------------------
#
# A hook is a separate process writing straight to stdout, so a driver knows
# only its exit status -- which is why doctor could never collapse a healthy
# module or count what an unhealthy one said. With DOT_UI_RECORDS set the
# printers emit "<RS>sev<FS>label<FS>message" instead of a rendered line, the
# driver captures the stream and renders it. It is exported, so a hook's own
# ok/warn/fail arrive in the same shape.
#
# Anything in the stream WITHOUT the marker is some other program's output
# (brew, defaults, a bare echo). Those lines are always shown: the collapse may
# only hide what has explicitly reported itself healthy.
#
# Two severities are the protocol talking to itself rather than a printer:
# `foldopen` and `foldshut` bracket one child process, and carry the exit status
# fold_status folded into the tallies so ui_group can reconcile that one number
# with the findings the child actually recorded.
__UI_RS=$'\036'
__UI_FS=$'\037'

# --- Printers ---------------------------------------------------------------
#
# ok|info|warn|fail LABEL MESSAGE  -- the label lands in the aligned column.
# ok|info|warn|fail MESSAGE        -- one argument, no label, message at the
#                                     column's left edge.

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
# shape. WIDTH is for the group lines, whose label is a module name and so needs
# room the field names below it do not.
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

  # dim and say carry no marker of their own -- an aside must not get the weight
  # the caller chose not to give it -- but they still leave the slot empty
  # rather than absent, or their label would sit two columns left of every
  # other line in the same block.
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

# --- Structure --------------------------------------------------------------

# heading TITLE [NOTE] -- a section divider ruled to the terminal width, with
# the note right-aligned: "── Modules ──────────────────── 9 enabled".
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

# step CURRENT TOTAL NAME [NOTE] -- one line where a heading plus a dim
# description used to be two: "▸ [3/9] containers   Docker via colima". An empty
# CURRENT drops the counter, for a phase that is not one of the numbered ones.
step() {
  local i=$1 n=$2 name=$3 note=${4:-} counter=''
  if [[ -n $i ]]; then printf -v counter '[%s/%s] ' "$i" "$n"; fi
  printf '\n%s  %s%s%s %s%s%s%s%-*s%s %s%s%s\n' \
    "$DOT_UI_INDENT" "$__C_BOLD" "$__G_STEP" "$__C_RESET" \
    "$__C_DIM" "$counter" "$__C_RESET" \
    "$__C_BOLD" "$__UI_GROUP_W" "$name" "$__C_RESET" \
    "$__C_DIM" "$note" "$__C_RESET"
}

# ui_quote -- another program's output, indented and dimmed. It has to keep
# streaming (a `brew bundle` that takes two minutes must be visible while it
# runs, not afterwards), but it must not read with the same weight as this
# repo's own lines. The caller keeps the status: ${PIPESTATUS[0]}.
ui_quote() {
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    printf '%s      %s%s%s\n' "$DOT_UI_INDENT" "$__C_DIM" "$line" "$__C_RESET"
  done
}

# --- Groups -----------------------------------------------------------------
#
# A module's whole report, collapsed to one line when every record in it is ok.
# DOT_VERBOSE expands them all again.

# Filled by ui_group so the run can end by repeating its problems instead of
# telling the reader to scroll up.
DOT_PROBLEMS=()
DOT_GROUPS_CLEAN=0
DOT_GROUPS_TOTAL=0

# ui_group NAME NOTE FILE -- render the captured stream in FILE as one group,
# and reconcile the tallies with what that stream actually says.
#
# The reconciliation is here because nowhere else can do it. A hook is a
# separate process: its own ok/warn/fail never touched this shell's counters,
# and fold_status could add only one for the exit status however many findings
# the hook reported -- three warnings came back as "1 warning". So a fold scope
# (fold_status's two markers, around one child) is read as: every finding inside
# it is added here, and the one fold_status counted for the status is taken back
# whenever the child named the problem itself.
#
# Records outside every fold scope were printed by THIS shell, which counted
# them as it printed them; they are left alone.
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
    # do not run hooks of their own. A nested scope would be read as the inner
    # one only -- the day a hook needs to fold a child, this needs a stack.
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
            # The child named the failure itself, so the roll-up would be the
            # same finding a second time under a tally that counted it once.
            # Only THIS child's records can say that -- a failure recorded
            # elsewhere in the group explains nothing about this one, and
            # dropping the roll-up over it lost the only line naming a hook
            # that died before it could print anything.
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

# Indented under the group's own line, and only the lines that earned the space:
# a check that passed inside a module that did not is noise unless asked for.
# `if`, never `test && continue`: a false test at the end of a loop body leaves
# status 1 and set -e kills the caller.
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

# ui_problems -- what the groups found, repeated under the verdict so the reader
# is not sent scrolling. Honest to count now: the records are the individual
# findings, not a hook's rolled-up exit status.
#
# Failures first, and capped: a list long enough to scroll is the thing this
# exists to replace. The cap is on the repeat only -- every line is still up
# there in full, and --verbose prints them all again here.
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

# --- The verdict ------------------------------------------------------------

# ui_count N NOUN -- "1 module", "9 modules". Every count in the output goes
# through it, so "core + 1 modules" cannot come back.
ui_count() {
  if (($1 == 1)); then printf '%s %s' "$1" "$2"; else printf '%s %ss' "$1" "$2"; fi
}

# ui_verdict GOOD-NEWS -- the last line a verb prints, and the problems it
# refers to, repeated. The tallies decide the words, never the record list: a
# failure printed outside a group is counted here even though nothing can
# repeat it, and a summary that contradicts the lines above it is the one
# thing this may not do.
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
  # everything outside one; blaming those on modules is the same summary saying
  # two different things. DOT_PROBLEMS holds exactly the grouped findings, so
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

# --- Status -----------------------------------------------------------------

# fold_status MESSAGE CMD... -- run a child process and fold its exit status
# back into the tallies. The child has already printed its own detail; MESSAGE
# only says which hook broke.
#
# Under the record protocol it brackets the child with a scope instead of
# printing a roll-up line: a status is one number and a child can have many
# findings, so ui_group -- which can see both -- decides what the roll-up and
# the tallies should be. Without records there is nobody to reconcile with, and
# the status is all there is to report.
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
# line uses, so an error reads like the rest of the output rather than like a
# stack trace. The last pair should say what to do next.
die() {
  local msg=$1
  shift
  __ui_render fail '' "$msg" >&2
  ui_nest
  while (($# > 1)); do
    __ui_render dim "$1" "$2" >&2
    shift 2
  done
  # An odd argument left over is a caller that meant to say something. Printing
  # it unlabelled beats dropping it, which is what a bare `while` pair loop does.
  if (($#)); then __ui_render dim '' "$1" >&2; fi
  ui_unnest
  exit 1
}
