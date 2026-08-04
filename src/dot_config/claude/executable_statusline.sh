#!/usr/bin/env bash
# Claude Code status line. Line 1: model · dir · git · PR. Line 2: context gauge ·
# tokens · cost · ±lines · quota · time. Written for bash 3.2 (macOS system bash).
set -euo pipefail

input="$(cat)"

# --- colors (ANSI-C quoted so the escape bytes are literal in the strings) ---
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
CYAN=$'\033[36m'
GRAY=$'\033[38;5;240m'
SEP=" ${DIM}·${RESET} "

# --- helpers ---

# Interpolate a green→yellow→red RGB triple for a 0-100 percentage.
gradient_rgb() {
    local pct=$1 r g b t
    if ((pct < 0)); then pct=0; fi
    if ((pct > 100)); then pct=100; fi
    if ((pct <= 50)); then
        t=$((pct * 100 / 50)) # 0..100 across green→yellow
        r=$((39 + (241 - 39) * t / 100))
        g=$((174 + (196 - 174) * t / 100))
        b=$((96 + (15 - 96) * t / 100))
    else
        t=$(((pct - 50) * 100 / 50)) # 0..100 across yellow→red
        r=$((241 + (231 - 241) * t / 100))
        g=$((196 + (76 - 196) * t / 100))
        b=$((15 + (60 - 15) * t / 100))
    fi
    printf '%d %d %d' "$r" "$g" "$b"
}

# Compact token count: 1234→1k, 200000→200k, 1000000→1.0M.
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

# Threshold color for a usage percentage (green <70, yellow <90, red otherwise).
pct_color() {
    if (($1 >= 90)); then
        printf '%s' "$RED"
    elif (($1 >= 70)); then
        printf '%s' "$YELLOW"
    else
        printf '%s' "$GREEN"
    fi
}

# Wrap text in an OSC 8 hyperlink (Cmd/Ctrl-click in supporting terminals).
osc8() { printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$1" "$2"; }

# --- parse every field in one jq call (jq startup dominates runtime) ---
# Numbers are stringified so join() accepts them; absent fields still emit a separator, keeping read positions aligned.
fields="$(jq -r '
    [ (.model.display_name // "?"),
      (.workspace.current_dir // ""),
      (.session_id // ""),
      (.cost.total_cost_usd // 0 | tostring),
      (.cost.total_duration_ms // 0 | tostring),
      (.cost.total_lines_added // 0 | tostring),
      (.cost.total_lines_removed // 0 | tostring),
      (.context_window.used_percentage // 0 | tostring),
      (.context_window.total_input_tokens // 0 | tostring),
      (.context_window.context_window_size // 0 | tostring),
      (.effort.level // ""),
      (.workspace.git_worktree // ""),
      (.pr.number // "" | tostring),
      (.pr.url // ""),
      (.pr.review_state // ""),
      (.rate_limits.five_hour.used_percentage // "" | tostring),
      (.rate_limits.seven_day.used_percentage // "" | tostring)
    ] | join("\u001f")' <<<"$input")"

IFS=$'\037' read -r \
    MODEL DIR SESSION_ID COST DURATION_MS LINES_ADDED LINES_REMOVED \
    PCT_RAW USED_TOKENS CTX_SIZE EFFORT WORKTREE \
    PR_NUMBER PR_URL PR_STATE FIVE_H SEVEN_D <<<"$fields"

PCT=${PCT_RAW%%.*}
PCT=${PCT:-0}

# --- git state, cached per session ---
CACHE_FILE="${TMPDIR:-/tmp}/claude-statusline-git-${SESSION_ID}"
CACHE_MAX_AGE=5

cache_is_stale() {
    [[ ! -f "$CACHE_FILE" ]] && return 0
    local mtime age
    mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
    age=$(($(date +%s) - mtime))
    ((age > CACHE_MAX_AGE))
}

if cache_is_stale; then
    if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
        # porcelain=v2 gives branch/ahead/behind/per-file status in one pass; awk tallies into a pipe-delimited cache line.
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
                printf "%s|%d|%d|%d|%d|%d|%d\n", head, staged + 0, modified + 0, \
                    untracked + 0, ahead + 0, behind + 0, conflicts + 0
            }' >"$CACHE_FILE" || printf '||||||\n' >"$CACHE_FILE"
    else
        printf '||||||\n' >"$CACHE_FILE"
    fi
fi
IFS='|' read -r BRANCH STAGED MODIFIED UNTRACKED AHEAD BEHIND CONFLICTS <"$CACHE_FILE"
STAGED=${STAGED:-0} MODIFIED=${MODIFIED:-0} UNTRACKED=${UNTRACKED:-0}
AHEAD=${AHEAD:-0} BEHIND=${BEHIND:-0} CONFLICTS=${CONFLICTS:-0}

# ============================ line 1: identity ============================
LINE1="${CYAN}${BOLD}${MODEL}${RESET}"
[[ -n "$EFFORT" ]] && LINE1+=" ${DIM}${EFFORT}${RESET}"
LINE1+="${SEP}📁 ${BOLD}${DIR##*/}${RESET}"

if [[ -n "$BRANCH" ]]; then
    if ((${#BRANCH} > 30)); then BRANCH="${BRANCH:0:29}…"; fi
    GIT="🌿 ${MAGENTA}${BRANCH}${RESET}"
    ((STAGED > 0)) && GIT+=" ${GREEN}+${STAGED}${RESET}"
    ((MODIFIED > 0)) && GIT+=" ${YELLOW}~${MODIFIED}${RESET}"
    ((UNTRACKED > 0)) && GIT+=" ${BLUE}?${UNTRACKED}${RESET}"
    ((CONFLICTS > 0)) && GIT+=" ${RED}✖${CONFLICTS}${RESET}"
    ((AHEAD > 0)) && GIT+=" ${CYAN}⇡${AHEAD}${RESET}"
    ((BEHIND > 0)) && GIT+=" ${CYAN}⇣${BEHIND}${RESET}"
    [[ -n "$WORKTREE" ]] && GIT+=" ${DIM}⑂${WORKTREE}${RESET}"
    LINE1+="${SEP}${GIT}"
fi

if [[ -n "$PR_NUMBER" ]]; then
    case "$PR_STATE" in
        approved) PR_BODY="${GREEN}✓ PR #${PR_NUMBER}${RESET}" ;;
        changes_requested) PR_BODY="${RED}✗ PR #${PR_NUMBER}${RESET}" ;;
        draft) PR_BODY="${DIM}PR #${PR_NUMBER} (draft)${RESET}" ;;
        *) PR_BODY="${YELLOW}PR #${PR_NUMBER}${RESET}" ;;
    esac
    if [[ -n "$PR_URL" ]]; then PR_BODY="$(osc8 "$PR_URL" "$PR_BODY")"; fi
    LINE1+="${SEP}${PR_BODY}"
fi

# ============================ line 2: vitals ============================
BAR_WIDTH=14
FILLED=$((PCT * BAR_WIDTH / 100))
if ((FILLED > BAR_WIDTH)); then FILLED=$BAR_WIDTH; fi
EMPTY=$((BAR_WIDTH - FILLED))
FILLED_STR="" EMPTY_STR=""
if ((FILLED > 0)); then
    printf -v tmp '%*s' "$FILLED" ''
    FILLED_STR="${tmp// /█}"
fi
if ((EMPTY > 0)); then
    printf -v tmp '%*s' "$EMPTY" ''
    EMPTY_STR="${tmp// /░}"
fi
read -r GR GG GB <<<"$(gradient_rgb "$PCT")"
printf -v BAR_COLOR '\033[38;2;%d;%d;%dm' "$GR" "$GG" "$GB"

LINE2="${BAR_COLOR}${FILLED_STR}${RESET}${GRAY}${EMPTY_STR}${RESET} ${BAR_COLOR}${PCT}%${RESET}"
if ((CTX_SIZE > 0)); then
    LINE2+=" ${DIM}$(fmt_tokens "$USED_TOKENS")/$(fmt_tokens "$CTX_SIZE")${RESET}"
fi

LINE2+="${SEP}💰 ${YELLOW}$(printf '$%.2f' "$COST")${RESET}"

if ((LINES_ADDED > 0 || LINES_REMOVED > 0)); then
    LINE2+="${SEP}${GREEN}+${LINES_ADDED}${RESET}${DIM}/${RESET}${RED}-${LINES_REMOVED}${RESET}"
fi

if [[ -n "$FIVE_H" || -n "$SEVEN_D" ]]; then
    LINE2+="${SEP}"
    if [[ -n "$FIVE_H" ]]; then
        h=${FIVE_H%%.*}
        LINE2+="5h $(pct_color "${h:-0}")${h:-0}%${RESET}"
    fi
    if [[ -n "$SEVEN_D" ]]; then
        d=${SEVEN_D%%.*}
        [[ -n "$FIVE_H" ]] && LINE2+=" "
        LINE2+="7d $(pct_color "${d:-0}")${d:-0}%${RESET}"
    fi
fi

DURATION_SEC=$((DURATION_MS / 1000))
LINE2+="${SEP}⏱ $((DURATION_SEC / 60))m $((DURATION_SEC % 60))s"

printf '%s\n%s\n' "$LINE1" "$LINE2"
