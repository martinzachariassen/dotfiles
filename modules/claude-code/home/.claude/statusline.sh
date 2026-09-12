#!/usr/bin/env bash
# Claude Code status line, two lines.
#   1: model + effort · dir · session tag · git · session diff · PR
#   2: context gauge | 5h/7d quota + reset countdown
#
# ANSI-16 colours only, so the bar follows the terminal theme. Icons are Nerd
# Font glyphs; the branch icon is the one starship.toml uses for git_branch.
set -euo pipefail

input="$(cat)"

RESET=$'\033[0m' BOLD=$'\033[1m' DIM=$'\033[2m'
RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m'
BLUE=$'\033[34m' MAGENTA=$'\033[35m' CYAN=$'\033[36m'
SEP=" ${DIM}·${RESET} "
DIVIDER=" ${DIM}|${RESET} "

I_DIR=$''           # fa-folder
I_BRANCH=$''        # pl-branch
I_TAG=$''           # fa-tag
I_DIFF=$''          # oct-diff -- keeps session +N distinct from git's +N
I_PR=$''            # oct-git_pull_request
I_OK=$''            # fa-check
I_NO=$''            # fa-times
I_CTX=$'\U000f035b' # md-memory
I_RESET_ICO=$''     # fa-refresh

# 1234 -> 1k, 1000000 -> 1.0M.
fmt_tokens() {
  local n=$1
  if ((n >= 1000000)); then
    printf '%d.%dM' $((n / 1000000)) $(((n % 1000000) / 100000))
  elif ((n >= 1000)); then
    printf '%dk' $((n / 1000))
  else
    printf '%d' "$n"
  fi
}

# Sub-minute collapses to "<1m" so it stops flickering.
fmt_eta() {
  local s=$1
  if ((s < 0)); then s=0; fi
  if ((s >= 86400)); then
    if (((s % 86400) / 3600 > 0)); then
      printf '%dd%dh' $((s / 86400)) $(((s % 86400) / 3600))
    else
      printf '%dd' $((s / 86400))
    fi
  elif ((s >= 3600)); then
    printf '%dh%02dm' $((s / 3600)) $(((s % 3600) / 60))
  elif ((s >= 60)); then
    printf '%dm' $((s / 60))
  else
    printf '<1m'
  fi
}

# Same 70/90 split as starship, so yellow means the same thing everywhere.
pct_color() {
  if (($1 >= 90)); then
    printf '%s' "$RED"
  elif (($1 >= 70)); then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

effort_label() {
  case "$1" in
    medium) printf 'med' ;;
    *) printf '%s' "$1" ;;
  esac
}

trunc() {
  local max=$1 s=$2
  if ((${#s} > max)); then printf '%s…' "${s:0:max-1}"; else printf '%s' "$s"; fi
}

# OSC 8 hyperlink.
osc8() {
  local esc=$'\033' st=$'\033\\'
  printf '%s]8;;%s%s%s%s]8;;%s' "$esc" "$1" "$st" "$2" "$esc" "$st"
}

# One jq call (its startup dominates runtime), joined on \037, which cannot
# appear in the values once control characters are stripped. Written as the jq
# escape \u001f, never a literal byte: editors and formatters silently drop it,
# and the whole record then lands in MODEL. The IFS below must stay in sync.
fields="$(jq -r '
    def clean: if . == null then "" else tostring | gsub("[[:cntrl:]]"; " ") end;
    def num: if . == null then 0 else . end;
    [ (.model.display_name // "?" | clean),
      (.workspace.current_dir // "" | clean),
      (.session_id // "" | clean),
      (.session_name // "" | clean),
      (.effort.level // "" | clean),
      (.context_window.used_percentage | num | floor | tostring),
      (.context_window.total_input_tokens | num | tostring),
      (.context_window.context_window_size | num | tostring),
      (.cost.total_lines_added | num | tostring),
      (.cost.total_lines_removed | num | tostring),
      (.pr.number // "" | tostring),
      (.pr.url // "" | clean),
      (.pr.review_state // "" | clean),
      (if .rate_limits.five_hour then (.rate_limits.five_hour.used_percentage | num | floor | tostring) else "" end),
      (if .rate_limits.five_hour.resets_at then (.rate_limits.five_hour.resets_at - now | floor | tostring) else "" end),
      (if .rate_limits.seven_day then (.rate_limits.seven_day.used_percentage | num | floor | tostring) else "" end),
      (if .rate_limits.seven_day.resets_at then (.rate_limits.seven_day.resets_at - now | floor | tostring) else "" end)
    ] | join("\u001f")' <<<"$input")"

IFS=$'\037' read -r \
  MODEL DIR SESSION_ID SESSION_NAME EFFORT PCT USED_TOKENS CTX_SIZE \
  LINES_ADDED LINES_REMOVED PR_NUMBER PR_URL PR_STATE \
  FIVE_H FIVE_H_ETA SEVEN_D SEVEN_D_ETA <<<"$fields"

SESSION_ID=${SESSION_ID:-default}
PCT=${PCT:-0} LINES_ADDED=${LINES_ADDED:-0} LINES_REMOVED=${LINES_REMOVED:-0} CTX_SIZE=${CTX_SIZE:-0}

# --- line 1: identity -------------------------------------------------------
LINE1="${CYAN}${BOLD}${MODEL}${RESET}"
[[ -n $EFFORT ]] && LINE1+=" ${DIM}$(effort_label "$EFFORT")${RESET}"

if [[ -n $DIR ]]; then
  D="$(trunc 30 "${DIR##*/}")"
  LINE1+="${SEP}${DIM}${I_DIR}${RESET} ${BLUE}${BOLD}${D}${RESET}"
fi

if [[ -n $SESSION_NAME ]]; then
  S="$(trunc 28 "$SESSION_NAME")"
  LINE1+="${SEP}${DIM}${I_TAG}${RESET} ${DIM}${S}${RESET}"
fi

# Cached per session for a few seconds: the bar re-renders on every keystroke.
if [[ -n $DIR ]] && git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  cache="${TMPDIR:-/tmp}/claude-statusline-git-${SESSION_ID}"
  age=999
  if [[ -f $cache ]]; then
    mtime=$(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache" 2>/dev/null || echo 0)
    age=$(($(date +%s) - mtime))
  fi
  if ((age > 5)); then
    git -C "$DIR" status --porcelain=v2 --branch 2>/dev/null | awk '
            /^# branch.head / { head = $3 }
            /^# branch.ab / { ahead = $3; behind = $4 }
            /^[12] / {
                if (substr($2, 1, 1) != ".") staged++
                if (substr($2, 2, 1) != ".") modified++
            }
            /^u / { conflicts++ }
            /^\? / { untracked++ }
            END {
                gsub(/[+-]/, "", ahead); gsub(/[+-]/, "", behind)
                printf "%s|%d|%d|%d|%d|%d|%d\n", head, staged+0, modified+0, \
                    untracked+0, ahead+0, behind+0, conflicts+0
            }
        ' >"$cache" || printf '||||||\n' >"$cache"
  fi
  IFS='|' read -r BRANCH STAGED MODIFIED UNTRACKED AHEAD BEHIND CONFLICTS <"$cache"
  STAGED=${STAGED:-0} MODIFIED=${MODIFIED:-0} UNTRACKED=${UNTRACKED:-0}
  AHEAD=${AHEAD:-0} BEHIND=${BEHIND:-0} CONFLICTS=${CONFLICTS:-0}
  if [[ -n $BRANCH && $BRANCH != '(detached)' ]]; then
    B="$(trunc 32 "$BRANCH")"
    G="${DIM}${I_BRANCH}${RESET} ${MAGENTA}${B}${RESET}"
    ((STAGED > 0)) && G+=" ${GREEN}+${STAGED}${RESET}"
    ((MODIFIED > 0)) && G+=" ${YELLOW}!${MODIFIED}${RESET}"
    ((UNTRACKED > 0)) && G+=" ${BLUE}?${UNTRACKED}${RESET}"
    ((CONFLICTS > 0)) && G+=" ${RED}✗${CONFLICTS}${RESET}"
    ((AHEAD > 0)) && G+=" ${CYAN}⇡${AHEAD}${RESET}"
    ((BEHIND > 0)) && G+=" ${CYAN}⇣${BEHIND}${RESET}"
    LINE1+="${SEP}${G}"
  fi
fi

if ((LINES_ADDED > 0 || LINES_REMOVED > 0)); then
  LINE1+="${SEP}${DIM}${I_DIFF}${RESET} ${GREEN}+${LINES_ADDED}${RESET}${DIM}/${RESET}${RED}-${LINES_REMOVED}${RESET}"
fi

if [[ -n $PR_NUMBER ]]; then
  case "$PR_STATE" in
    approved) PR_TEXT="${GREEN}${I_OK} #${PR_NUMBER}${RESET}" ;;
    changes_requested) PR_TEXT="${RED}${I_NO} #${PR_NUMBER}${RESET}" ;;
    draft) PR_TEXT="${DIM}${I_PR} #${PR_NUMBER} draft${RESET}" ;;
    *) PR_TEXT="${YELLOW}${I_PR} #${PR_NUMBER}${RESET}" ;;
  esac
  [[ -n $PR_URL ]] && PR_TEXT="$(osc8 "$PR_URL" "$PR_TEXT")"
  LINE1+="${SEP}${PR_TEXT}"
fi

# --- line 2: budget ---------------------------------------------------------
BAR_WIDTH=14
FILLED=$((PCT * BAR_WIDTH / 100))
((FILLED > BAR_WIDTH)) && FILLED=$BAR_WIDTH
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
((FILLED > 0)) && printf -v tmp '%*s' "$FILLED" '' && BAR+="${tmp// /█}"
((EMPTY > 0)) && printf -v tmp '%*s' "$EMPTY" '' && BAR+="${tmp// /░}"
BAR_COLOR="$(pct_color "$PCT")"

LINE2="${DIM}${I_CTX}${RESET} ${BAR_COLOR}${BAR}${RESET} ${BAR_COLOR}${PCT}%${RESET}"
if ((CTX_SIZE > 0)); then
  T="$(fmt_tokens "$USED_TOKENS")/$(fmt_tokens "$CTX_SIZE")"
  LINE2+="${SEP}${DIM}${T}${RESET}"
fi

QUOTA=""
if [[ -n $FIVE_H ]]; then
  QUOTA="5h${DIM}:${RESET}$(pct_color "$FIVE_H")${FIVE_H}%${RESET}"
  [[ -n $FIVE_H_ETA ]] && QUOTA+=" ${DIM}${I_RESET_ICO} $(fmt_eta "$FIVE_H_ETA")${RESET}"
fi
if [[ -n $SEVEN_D ]]; then
  [[ -n $QUOTA ]] && QUOTA+="$SEP"
  QUOTA+="7d${DIM}:${RESET}$(pct_color "$SEVEN_D")${SEVEN_D}%${RESET}"
  [[ -n $SEVEN_D_ETA ]] && QUOTA+=" ${DIM}${I_RESET_ICO} $(fmt_eta "$SEVEN_D_ETA")${RESET}"
fi
[[ -n $QUOTA ]] && LINE2+="${DIVIDER}${QUOTA}"

printf '%s\n%s\n' "$LINE1" "$LINE2"
