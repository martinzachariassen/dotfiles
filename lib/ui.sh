# shellcheck shell=bash
#
# Terminal output. The only file that emits colour or glyphs, and the only one
# that decides where a column starts; tests/contract.bats holds both.

# Settled at source time, the last moment stdout is still the terminal.
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

# For bin/dot's transcript sed. Here, so colour is spelled in one file only.
__UI_STRIP_SGR="s/$(printf '\033')\[[0-9;]*m//g"

# One column wide in both alphabets, so the label column never moves.
__ui_locale=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
if [[ ${DOT_ASCII:-} == 1 ]] ||
  [[ $__ui_locale != *UTF-8* && $__ui_locale != *UTF8* && $__ui_locale != *utf8* ]]; then
  __G_OK='+' __G_FAIL='x' __G_WARN='!' __G_INFO='>' __G_STEP='*' __G_RULE='-'
else
  __G_OK='✓' __G_FAIL='✗' __G_WARN='▲' __G_INFO='→' __G_STEP='▸' __G_RULE='─'
fi
unset __ui_locale

# tput needs a terminal, and the transcript's pipe is not one.
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

# The label column. Callers pass a bare label; the wider one is for groups.
__UI_LABEL_W=12
__UI_GROUP_W=14

# Exported, so a hook's output nests under its step line.
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

# 3, not 2: bash owns 2 for syntax errors.
DOT_STATUS_WARN=3

# Records: with DOT_UI_RECORDS the printers emit "<RS>sev<FS>label<FS>message"
# for the driver to render. See docs/architecture.md#records.
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

  # No marker for dim and say, but the slot stays, or their label shifts left.
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

ui_elapsed() {
  local s=$1
  if ((s >= 60)); then
    printf '%dm%02ds' $((s / 60)) $((s % 60))
  else
    printf '%ds' "$s"
  fi
}

# ui_quote -- another program's output, streamed, indented and dimmed, with a
# heartbeat while it is silent. `read -t` sits in an `if` so set -e survives a
# timeout; `chunk` accumulates because a timeout can split a line.
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

# Filled by ui_group, repeated under the verdict.
DOT_PROBLEMS=()
DOT_GROUPS_CLEAN=0
DOT_GROUPS_TOTAL=0

# ui_group NAME NOTE FILE -- one group, collapsed to a line when all is ok.
# The only place that sees both a child's status and its findings, so the
# tallies are reconciled here. See docs/architecture.md#records.
ui_group() {
  local name=$1 note=$2 file=$3
  local line sev label msg rest entry counted raw=0
  local -a detail=()
  local worst='ok'
  local in_fold=0 fold_fail=0 fold_warn=0 add_fail=0 add_warn=0

  while IFS= read -r line; do
    if [[ $line != "$__UI_RS"* ]]; then
      # Another program's output: never hidden, so the group cannot collapse.
      if [[ -n $line ]]; then
        detail+=("raw$__UI_FS$__UI_FS$line")
        raw=1
      fi
      continue
    fi
    rest=${line#"$__UI_RS"}
    sev=${rest%%"$__UI_FS"*}
    rest=${rest#*"$__UI_FS"}

    # Flat: hooks do not run hooks. If one ever does, this needs a stack.
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
            # Only this child's own records cancel its roll-up, or a hook that
            # died silently loses the one line naming it.
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

    # The line already carries the group's name; do not say it twice.
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

# Passed checks in a failing group only under --verbose.
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

# ui_problems -- the groups' findings under the verdict, failures first. The
# cap is on the repeat only; every line is still printed above.
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

# ui_count N NOUN -- "1 module", "9 modules"; every count goes through it.
ui_count() {
  if (($1 == 1)); then printf '%s %s' "$1" "$2"; else printf '%s %ss' "$1" "$2"; fi
}

# ui_verdict GOOD-NEWS -- the last line, worded from the tallies, never the
# record list: it may not contradict the lines above it.
ui_verdict() {
  local good=$1 unit=${2:-group} line=''

  if ((DOT_FAILURES > 0)); then
    line=$(ui_count "$DOT_FAILURES" problem)
    if ((DOT_WARNINGS > 0)); then line+=", $(ui_count "$DOT_WARNINGS" warning)"; fi
  elif ((DOT_WARNINGS > 0)); then
    line=$(ui_count "$DOT_WARNINGS" warning)
  fi

  # "in X of Y modules" only when DOT_PROBLEMS accounts for every finding:
  # orphans, and all of apply and remove, print outside any group.
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

# fold_status MESSAGE CMD... -- fold a child's exit status into the tallies.
# Under records it brackets the child instead, and ui_group decides the roll-up.
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
