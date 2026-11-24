# shellcheck shell=bash

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

__UI_STRIP_SGR="s/$(printf '\033')\[[0-9;]*[mFK]//g"
__UI_FRAME_SED="/$(printf '\033')\[28m/b"

__ui_locale=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
if [[ ${DOT_ASCII:-} == 1 ]] ||
  [[ $__ui_locale != *UTF-8* && $__ui_locale != *UTF8* && $__ui_locale != *utf8* ]]; then
  __G_OK='+' __G_FAIL='x' __G_WARN='!' __G_INFO='>' __G_STEP='*' __G_RULE='-'
  __G_MORE='...' __G_SPIN="|/-\\" __G_BAR='#' __G_BAR_HALF='#' __G_BAR_EMPTY='-'
  __G_ON='*' __G_OFF='o' __G_DOT='-'
else
  __G_OK='✓' __G_FAIL='✗' __G_WARN='▲' __G_INFO='→' __G_STEP='▸' __G_RULE='─'
  __G_MORE='…' __G_SPIN='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' __G_BAR='━' __G_BAR_HALF='╸' __G_BAR_EMPTY='━'
  __G_ON='●' __G_OFF='○' __G_DOT='·'
fi
unset __ui_locale

# Settled at source time like colour: a hook's stdout is a pipe, so only the
# driver that owns the terminal ever draws.
if [[ ${DOT_PROGRESS:-} == 1 ]]; then
  __UI_LIVE=1
elif [[ ${DOT_PROGRESS:-} == 0 || ! -t 1 ]]; then
  __UI_LIVE=0
else
  __UI_LIVE=1
fi

# A frame is a whole line, so it keeps its place in the transcript's
# line-buffered stream; the transcript drops any line carrying this tag.
__UI_FRAME=$'\033[28m'

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

__UI_LABEL_W=12
__UI_GROUP_W=14

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

__UI_RS=$'\036'
__UI_FS=$'\037'

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

__ui_fit() {
  local text=$1 room=$2
  if ((room < ${#__G_MORE} + 1)); then room=$((${#__G_MORE} + 1)); fi
  if ((${#text} <= room)); then
    printf '%s' "$text"
  else
    printf '%s%s' "${text:0:room-${#__G_MORE}}" "$__G_MORE"
  fi
}

# A message may end in a tab and a short note, which goes flush right.
__ui_render() {
  local sev=$1 label=$2 msg=$3 width=${4:-$__UI_LABEL_W} glyph colour body
  local right='' room pad

  if [[ $msg == *$'\t'* ]]; then
    right=${msg#*$'\t'}
    msg=${msg%%$'\t'*}
  fi

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

  if [[ -n $right ]]; then
    room=$((__UI_COLS - ${#DOT_UI_INDENT} - 4 - ${#right} - 2))
    body=$(__ui_fit "$body" "$room")
    # Padded by hand: printf pads bytes, and a middle dot is two of them.
    printf -v pad '%*s' $((room - ${#body} + 2)) ''
    body+="$pad$__C_DIM$right$__C_RESET"
  fi

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

heading() {
  local title=$1 note=${2:-} tone=${3:-} left right fill n colour=''

  left="$__G_RULE$__G_RULE $title "
  if [[ -n $note ]]; then right=" $note"; else right=''; fi
  if [[ $tone == warn ]]; then colour=$__C_YELLOW$__C_BOLD; fi

  n=$((__UI_COLS - ${#left} - ${#right}))
  ((n > 0)) || n=1
  printf -v fill '%*s' "$n" ''
  fill=${fill// /$__G_RULE}

  printf '\n%s%s%s%s%s%s%s%s\n' \
    "$__C_BOLD" "$left" "$__C_RESET$__C_DIM" "$fill" "$__C_RESET" \
    "$colour" "$right" "${colour:+$__C_RESET}"
}

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

# Microseconds. Digits only: EPOCHREALTIME takes the locale's decimal mark.
ui_now() { printf '%s\n' "${EPOCHREALTIME//[!0-9]/}"; }

ui_duration() {
  local us=$1 s tenths
  ((us >= 0)) || us=0
  s=$((us / 1000000))
  if ((s >= 60)); then
    ui_elapsed "$s"
  else
    tenths=$((us / 100000 % 10))
    printf '%d.%ds' "$s" "$tenths"
  fi
}

ui_megabytes() {
  local bytes=$1
  if ((bytes >= 10000000)); then
    printf '%d MB' $((bytes / 1000000))
  else
    printf '%d.%d MB' $((bytes / 1000000)) $((bytes / 100000 % 10))
  fi
}

__ui_quoted() {
  printf '%s      %s%s%s\n' "$DOT_UI_INDENT" "$__C_DIM" "$1" "$__C_RESET"
}

ui_quote() {
  local line='' chunk status idle=0 beat=${DOT_UI_HEARTBEAT:-15}
  while true; do
    chunk=''
    # `read -t` sits in an `if` so set -e survives a timeout; `chunk` accumulates
    # because a timeout can split a line.
    if IFS= read -r -t "$beat" chunk; then status=0; else status=$?; fi
    line+=$chunk
    if ((status > 128)); then
      idle=$((idle + beat))
      dim "no output for $(ui_elapsed "$idle") -- still running"
      continue
    fi
    idle=0
    if ((status == 0)) || [[ -n $line ]]; then
      __ui_quoted "$line"
    fi
    line=''
    ((status == 0)) || break
  done
}

ui_frame() {
  ((__UI_LIVE)) || return 0
  printf '%s%s\n' "$__UI_FRAME" "$1"
}

ui_progress() {
  local name=$1 got=$2 total=$3 rate=$4 us=$5 tick=$6
  local spin head body tail='' bar fill w full half secs clock

  spin=${__G_SPIN:tick%${#__G_SPIN}:1}
  printf -v head '%s      %s%s%s %-*s ' "$DOT_UI_INDENT" "$__C_BLUE" "$spin" "$__C_RESET" \
    "$__UI_LABEL_W" "$(__ui_fit "$name" "$__UI_LABEL_W")"
  secs=$((us / 1000000))
  printf -v clock '%d:%02d' $((secs / 60)) $((secs % 60))

  if ((total > 0 && got > 0)); then
    ((got <= total)) || got=$total
    tail="  $(printf '%3d' $((got * 100 / total)))%  $((got / 1000000))/$(ui_megabytes "$total")"
    if ((rate > 0 && __UI_COLS >= 72)); then
      secs=$(((total - got) / rate))
      tail+="  $(ui_megabytes "$rate")/s"
      ((secs < 1)) || tail+="  ~$(ui_elapsed "$secs")"
    fi
    w=$((__UI_COLS - ${#DOT_UI_INDENT} - 21 - ${#tail} - 1))
    ((w <= 24)) || w=24
    ((w >= 6)) || w=6
    full=$((got * w / total))
    half=$(((got * w * 2 / total) % 2))
    ((full < w)) || half=0
    printf -v fill '%*s' "$full" ''
    bar="$__C_GREEN${fill// /$__G_BAR}"
    ((half)) && bar+=$__G_BAR_HALF
    printf -v fill '%*s' $((w - full - half)) ''
    bar+="$__C_RESET$__C_DIM${fill// /$__G_BAR_EMPTY}$__C_RESET"
    body="$bar$tail"
  elif ((got > 0)); then
    body="downloading  $__C_DIM$(ui_megabytes "$got")"
    if ((rate > 0)); then body+=" $__G_DOT $(ui_megabytes "$rate")/s"; fi
    body+=" $__G_DOT $clock$__C_RESET"
  else
    body="installing  $__C_DIM$clock$__C_RESET"
  fi
  ui_frame "$head$body"
}

# The driver's side of a module while it applies: held back while every record
# is good news, so a module with nothing to do costs one line; let out the
# moment something changes, so a slow install is watched rather than awaited.
__UI_TALLY=''

__ui_lg_item() {
  local DOT_UI_INDENT="$DOT_UI_INDENT    "
  __ui_render "$@"
}

__ui_lg_unframe() {
  if ((framed)); then printf '\033[F\033[2K'; fi
  framed=0
}

__ui_lg_open() {
  local entry room
  ((held)) || return 0
  held=0
  room=$((__UI_COLS - ${#DOT_UI_INDENT} - 4 - __UI_GROUP_W - 1))
  printf '%s  %s%s %-*s%s %s%s%s\n' "$DOT_UI_INDENT" "$__C_BOLD" "$__G_STEP" \
    "$__UI_GROUP_W" "$name" "$__C_RESET" "$__C_DIM" "$(__ui_fit "$note" "$room")" "$__C_RESET"
  for entry in ${kept[@]+"${kept[@]}"}; do
    __ui_lg_item "${entry%%"$__UI_FS"*}" "$(__ui_lg_field 1 "$entry")" "$(__ui_lg_field 2 "$entry")"
  done
  kept=()
}

__ui_lg_field() {
  local n=$1 rest=$2
  rest=${rest#*"$__UI_FS"}
  if ((n == 2)); then rest=${rest#*"$__UI_FS"}; else rest=${rest%%"$__UI_FS"*}; fi
  printf '%s' "$rest"
}

ui_live_group() {
  local name=$1 note=$2 start line rest sev label msg text
  local held=1 framed=0 changes=0 fails=0 warns=0 fold_fail=0 fold_warn=0
  local -a kept=() said=()
  start=$(ui_now)

  while IFS= read -r line; do
    if [[ $line == "$__UI_FRAME"* ]]; then
      __ui_lg_open
      if ((framed)); then printf '\033[F'; fi
      printf '\033[2K%s\n' "$line"
      framed=1
      continue
    fi
    if [[ $line != "$__UI_RS"* ]]; then
      [[ -n $line ]] || continue
      __ui_lg_open
      __ui_lg_unframe
      printf '%s\n' "$line"
      continue
    fi

    rest=${line#"$__UI_RS"}
    sev=${rest%%"$__UI_FS"*}
    rest=${rest#*"$__UI_FS"}
    case $sev in
      foldopen)
        fold_fail=0 fold_warn=0
        continue
        ;;
      foldshut)
        label=${rest%%"$__UI_FS"*}
        msg=${rest#*"$__UI_FS"}
        if [[ $label == fail ]] && ((fold_fail == 0)); then
          sev=fail
        elif [[ $label == warn ]] && ((fold_fail + fold_warn == 0)); then
          sev=warn
        else
          continue
        fi
        label=''
        ;;
      *)
        label=${rest%%"$__UI_FS"*}
        msg=${rest#*"$__UI_FS"}
        ;;
    esac

    if ((held)) && [[ $sev == ok || $sev == dim ]]; then
      kept+=("$sev$__UI_FS$label$__UI_FS$msg")
      if [[ $sev == ok ]]; then said+=("${msg%%$'\t'*}"); fi
      continue
    fi

    case $sev in
      info)
        changes=$((changes + 1))
        if [[ -n $__UI_TALLY ]]; then printf '%s\t%s\n' "$label" "${msg%% *}" >>"$__UI_TALLY"; fi
        ;;
      fail) fails=$((fails + 1)) fold_fail=$((fold_fail + 1)) ;;
      warn) warns=$((warns + 1)) fold_warn=$((fold_warn + 1)) ;;
    esac
    __ui_lg_open
    __ui_lg_unframe
    __ui_lg_item "$sev" "$label" "$msg"
  done

  msg=$(ui_duration $(($(ui_now) - start)))
  if ((held)); then
    if ((${#said[@]})); then
      text=$(ui_join "${said[@]}")
    else
      text=$note
    fi
    __ui_render ok "$name" "$text"$'\t'"$msg" "$__UI_GROUP_W"
    return 0
  fi

  __ui_lg_unframe
  if ((fails)); then
    __ui_lg_item fail '' "$(ui_count "$fails" problem)"$'\t'"$msg"
  elif ((warns)); then
    __ui_lg_item warn '' "$(ui_count "$warns" warning)"$'\t'"$msg"
  elif ((changes)); then
    __ui_lg_item ok '' "$(ui_count "$changes" change)"$'\t'"$msg"
  else
    __ui_lg_item ok '' "done"$'\t'"$msg"
  fi
}

# Reads what every group's changes were, from the tally file, as one line.
ui_changes() {
  local file=$1 label word n=0 casks=0 formulae=0 runtimes=0 extensions=0 plugins=0 links=0 moved=0 written=0 part
  local -A other=()
  local -a parts=() order=()
  [[ -f $file ]] || return 0
  while IFS=$'\t' read -r label word; do
    n=$((n + 1))
    case $label in
      install)
        if [[ $word == cask ]]; then casks=$((casks + 1)); else formulae=$((formulae + 1)); fi
        ;;
      link | relink) links=$((links + 1)) ;;
      backup) moved=$((moved + 1)) ;;
      write) written=$((written + 1)) ;;
      runtime) runtimes=$((runtimes + 1)) ;;
      extension) extensions=$((extensions + 1)) ;;
      plugin) plugins=$((plugins + 1)) ;;
      *)
        [[ -n ${other[$label]:-} ]] || order+=("$label")
        other[$label]=$((${other[$label]:-0} + 1))
        ;;
    esac
  done <"$file"
  ((n)) || return 0

  ((casks)) && parts+=("$(ui_count "$casks" cask)")
  ((formulae)) && parts+=("$(ui_count "$formulae" formula)")
  ((runtimes)) && parts+=("$(ui_count "$runtimes" runtime)")
  ((extensions)) && parts+=("$(ui_count "$extensions" extension)")
  ((plugins)) && parts+=("$(ui_count "$plugins" plugin)")
  ((links)) && parts+=("$(ui_count "$links" link)")
  ((written)) && parts+=("$(ui_count "$written" file) written")
  ((moved)) && parts+=("$moved moved to backups")
  for label in ${order[@]+"${order[@]}"}; do parts+=("${other[$label]} $label"); done
  printf '%s\t%s\n' "$n" "$(ui_join "${parts[@]}")"
}

DOT_PROBLEMS=()
DOT_GROUPS_CLEAN=0
DOT_GROUPS_TOTAL=0

ui_group() {
  local name=$1 note=$2 file=$3
  local line sev label msg rest entry counted raw=0
  local -a detail=()
  local worst='ok'
  local in_fold=0 fold_fail=0 fold_warn=0 add_fail=0 add_warn=0

  while IFS= read -r line; do
    if [[ $line != "$__UI_RS"* ]]; then
      if [[ -n $line ]]; then
        detail+=("raw$__UI_FS$__UI_FS$line")
        raw=1
      fi
      continue
    fi
    rest=${line#"$__UI_RS"}
    sev=${rest%%"$__UI_FS"*}
    rest=${rest#*"$__UI_FS"}

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
  if [[ $worst == ok ]]; then
    DOT_GROUPS_CLEAN=$((DOT_GROUPS_CLEAN + 1))
    if [[ -n ${DOT_UI_HIDE_CLEAN:-} && -z ${DOT_VERBOSE:-} && $raw == 0 ]]; then return 0; fi
    note=$(__ui_checked "$name" "$note" ${detail[@]+"${detail[@]}"})
  fi

  __ui_render "$worst" "$name" "$(__ui_fit "$note" $((__UI_COLS - ${#DOT_UI_INDENT} - 5 - __UI_GROUP_W)))" "$__UI_GROUP_W"
  if [[ $worst != ok ]] || ((raw)) || [[ -n ${DOT_VERBOSE:-} ]]; then
    __ui_detail ${detail[@]+"${detail[@]}"}
  fi
}

# A clean group names what passed rather than repeating its description.
__ui_checked() {
  local name=$1 note=$2 entry sev label out=''
  local -A seen=()
  shift 2
  for entry in "$@"; do
    sev=${entry%%"$__UI_FS"*}
    entry=${entry#*"$__UI_FS"}
    label=${entry%%"$__UI_FS"*}
    [[ $sev == ok && -n $label && $label != "$name" && -z ${seen[$label]:-} ]] || continue
    seen[$label]=1
    out+=" $__G_DOT $label"
  done
  if [[ -n $out ]]; then printf '%s\n' "${out:3}"; else printf '%s\n' "$note"; fi
}

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

ui_count() {
  if (($1 == 1)); then printf '%s %s' "$1" "$2"; else printf '%s %ss' "$1" "$2"; fi
}

ui_verdict() {
  local good=$1 unit=${2:-group} line=''

  if ((DOT_FAILURES > 0)); then
    line=$(ui_count "$DOT_FAILURES" problem)
    if ((DOT_WARNINGS > 0)); then line+=", $(ui_count "$DOT_WARNINGS" warning)"; fi
  elif ((DOT_WARNINGS > 0)); then
    line=$(ui_count "$DOT_WARNINGS" warning)
  fi

  if ((DOT_GROUPS_TOTAL > 0 && DOT_FAILURES + DOT_WARNINGS > 0)) &&
    ((${#DOT_PROBLEMS[@]} == DOT_FAILURES + DOT_WARNINGS)); then
    line+=" in $((DOT_GROUPS_TOTAL - DOT_GROUPS_CLEAN)) of $(ui_count "$DOT_GROUPS_TOTAL" "$unit")"
  fi

  if ((DOT_FAILURES > 0)); then
    fail "$line"
  elif ((DOT_WARNINGS > 0)); then
    warn "$line"
  else
    if [[ -n $good ]]; then ok "$good"; fi
    return 0
  fi

  ui_problems
  if ((DOT_GROUPS_CLEAN > 0)); then
    ok "$(ui_count "$DOT_GROUPS_CLEAN" "$unit") clean"
  fi
}

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

die() {
  local msg=$1
  shift
  __ui_render fail '' "$msg" >&2
  ui_nest
  while (($# > 1)); do
    __ui_render dim "$1" "$2" >&2
    shift 2
  done
  if (($#)); then __ui_render dim '' "$1" >&2; fi
  ui_unnest
  exit 1
}

ui_legend() {
  __ui_render ok '' 'passed, or already the way the repo wants it'
  __ui_render info '' 'a change, announced before it is made'
  __ui_render warn '' 'worth a look; the run still passes'
  __ui_render fail '' 'a problem; the run exits 1'
  __ui_render step '' 'a module with something to do, shown in full'
}

ui_toggle() {
  local on=$1 name=$2 desc=$3 glyph colour room
  if ((on)); then glyph=$__G_ON colour=$__C_GREEN; else glyph=$__G_OFF colour=$__C_DIM; fi
  room=$((__UI_COLS - ${#DOT_UI_INDENT} - 5 - __UI_GROUP_W))
  printf '%s  %s%s%s %-*s %s%s%s\n' "$DOT_UI_INDENT" "$colour" "$glyph" "$__C_RESET" \
    "$__UI_GROUP_W" "$name" "$__C_DIM" "$(__ui_fit "$desc" "$room")" "$__C_RESET"
}

ui_join() {
  local out='' part
  for part in "$@"; do out+=" $__G_DOT $part"; done
  printf '%s\n' "${out:3}"
}

ui_row() {
  __ui_render say "$2" "$3" "$1"
}

ui_warn_group() {
  __ui_render warn "$1" "$2" "$__UI_GROUP_W" >&2
  DOT_WARNINGS=$((DOT_WARNINGS + 1))
}
