#!/usr/bin/env bash
# Claude Code status line.
#   Line 1 — identity: model + mode flags · dir · git (with diff tally) · PR
#   Line 2 — budget: context gauge · cost + burn rate · api/wall time · quota + reset countdowns
# Written for bash 3.2 (macOS system bash).
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

# Elapsed duration, coarsest useful unit: 45s, 12m, 1h05m.
fmt_dur() {
    local s=$1
    if ((s >= 3600)); then
        printf '%dh%02dm' $((s / 3600)) $(((s % 3600) / 60))
    elif ((s >= 60)); then
        printf '%dm' $((s / 60))
    else
        printf '%ds' "$s"
    fi
}

# Countdown to a future instant. Sub-minute collapses to "<1m" so the value stops
# flickering once it no longer changes any decision.
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

# Small caps keep the effort level legible without competing with the model name.
effort_label() {
    case "$1" in
        low) printf 'ʟᴏᴡ' ;;
        medium) printf 'ᴍᴇᴅ' ;;
        high) printf 'ʜɪɢʜ' ;;
        xhigh) printf 'xʜɪɢʜ' ;;
        max) printf 'ᴍᴀx' ;;
        *) printf '%s' "$1" ;;
    esac
}

# Wrap text in an OSC 8 hyperlink (Cmd/Ctrl-click in supporting terminals).
osc8() { printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$1" "$2"; }

# --- parse every field in one jq call (jq startup dominates runtime) ---
# All float math happens here so bash only ever sees integers or printf-ready values.
# Numbers are stringified so join() accepts them; absent fields still emit a separator,
# keeping read positions aligned. Strings are stripped of control characters, which
# would otherwise break the \037-delimited read.
fields="$(jq -r '
    def clean: if . == null then "" else tostring | gsub("[[:cntrl:]]"; " ") end;
    def num: if . == null then 0 else . end;
    (.cost.total_duration_ms | num) as $dur |
    (.cost.total_cost_usd | num) as $cost |
    [ (.model.display_name // "?" | clean),
      (.workspace.current_dir // "" | clean),
      (.session_id // "" | clean),
      (.session_name // "" | clean),
      ($cost | tostring),
      (if $dur > 120000 and $cost > 0 then ($cost * 3600000 / $dur | tostring) else "" end),
      ($dur | tostring),
      (.cost.total_api_duration_ms | num | tostring),
      (.cost.total_lines_added | num | tostring),
      (.cost.total_lines_removed | num | tostring),
      (.context_window.used_percentage | num | tostring),
      (.context_window.total_input_tokens | num | tostring),
      (.context_window.context_window_size | num | tostring),
      (.effort.level // "" | clean),
      (.worktree.name // .workspace.git_worktree // "" | clean),
      (.pr.number // "" | tostring),
      (.pr.url // "" | clean),
      (.pr.review_state // "" | clean),
      (if .rate_limits.five_hour then (.rate_limits.five_hour.used_percentage | num | floor | tostring) else "" end),
      (if .rate_limits.five_hour.resets_at then (.rate_limits.five_hour.resets_at - now | floor | tostring) else "" end),
      (if .rate_limits.seven_day then (.rate_limits.seven_day.used_percentage | num | floor | tostring) else "" end),
      (if .rate_limits.seven_day.resets_at then (.rate_limits.seven_day.resets_at - now | floor | tostring) else "" end),
      (if .fast_mode then "1" else "" end),
      (if .exceeds_200k_tokens then "1" else "" end),
      (if .thinking.enabled == false then "1" else "" end),
      (.agent.name // "" | clean),
      (.vim.mode // "" | clean),
      ((.workspace.added_dirs // []) | length | tostring),
      (.output_style.name // "" | clean)
    ] | join("\u001f")' <<<"$input")"

IFS=$'\037' read -r \
    MODEL DIR SESSION_ID SESSION_NAME COST RATE DURATION_MS API_MS \
    LINES_ADDED LINES_REMOVED PCT_RAW USED_TOKENS CTX_SIZE EFFORT WORKTREE \
    PR_NUMBER PR_URL PR_STATE FIVE_H FIVE_H_ETA SEVEN_D SEVEN_D_ETA \
    FAST_MODE BIG_CTX NO_THINKING AGENT_NAME VIM_MODE ADDED_DIRS OUTPUT_STYLE <<<"$fields"

PCT=${PCT_RAW%%.*}
PCT=${PCT:-0}
COST=${COST:-0}
DURATION_MS=${DURATION_MS:-0}
API_MS=${API_MS:-0}
LINES_ADDED=${LINES_ADDED:-0}
LINES_REMOVED=${LINES_REMOVED:-0}
USED_TOKENS=${USED_TOKENS:-0}
CTX_SIZE=${CTX_SIZE:-0}
ADDED_DIRS=${ADDED_DIRS:-0}

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
# Mode flags render only when they deviate from the default, so the line stays
# quiet until something is actually worth knowing.
LINE1="${CYAN}${BOLD}${MODEL}${RESET}"
[[ -n "$EFFORT" ]] && LINE1+=" ${DIM}$(effort_label "$EFFORT")${RESET}"
[[ -n "$FAST_MODE" ]] && LINE1+=" ${YELLOW}⚡${RESET}"
[[ -n "$BIG_CTX" ]] && LINE1+=" ${YELLOW}1M${RESET}" # past 200k: premium-tier pricing
[[ -n "$NO_THINKING" ]] && LINE1+=" ${DIM}🧠off${RESET}"
[[ -n "$VIM_MODE" && "$VIM_MODE" != "INSERT" ]] && LINE1+=" ${MAGENTA}${VIM_MODE}${RESET}"
[[ -n "$AGENT_NAME" ]] && LINE1+=" ${DIM}🤖${AGENT_NAME}${RESET}"
[[ -n "$OUTPUT_STYLE" && "$OUTPUT_STYLE" != "default" ]] && LINE1+=" ${DIM}${OUTPUT_STYLE}${RESET}"

LINE1+="${SEP}📁 ${BOLD}${DIR##*/}${RESET}"
((ADDED_DIRS > 0)) && LINE1+=" ${DIM}+${ADDED_DIRS}dir${RESET}"
[[ -n "$SESSION_NAME" ]] && LINE1+=" ${DIM}🏷 ${SESSION_NAME}${RESET}"

DIFF=""
if ((LINES_ADDED > 0 || LINES_REMOVED > 0)); then
    DIFF="${GREEN}+${LINES_ADDED}${RESET}${DIM}/${RESET}${RED}-${LINES_REMOVED}${RESET}"
fi

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
    [[ -n "$DIFF" ]] && GIT+=" ${DIFF}"
    LINE1+="${SEP}${GIT}"
elif [[ -n "$DIFF" ]]; then
    LINE1+="${SEP}${DIFF}"
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

# ============================ line 2: budget ============================
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
# Burn rate stays hidden for the first two minutes, where it is pure noise.
[[ -n "$RATE" ]] && LINE2+=" ${DIM}$(printf '$%.2f/h' "$RATE")${RESET}"

# api/wall separates "waiting on the model" from "session has been open".
LINE2+="${SEP}⏱ ${DIM}$(fmt_dur $((API_MS / 1000)))/$(fmt_dur $((DURATION_MS / 1000)))${RESET}"

# Quota percentage answers "how much is left", the countdown answers "for how long" —
# neither is actionable without the other.
if [[ -n "$FIVE_H" ]]; then
    LINE2+="${SEP}5h $(pct_color "$FIVE_H")${FIVE_H}%${RESET}"
    [[ -n "$FIVE_H_ETA" ]] && LINE2+=" ${DIM}↻$(fmt_eta "$FIVE_H_ETA")${RESET}"
fi
if [[ -n "$SEVEN_D" ]]; then
    LINE2+="${SEP}7d $(pct_color "$SEVEN_D")${SEVEN_D}%${RESET}"
    [[ -n "$SEVEN_D_ETA" ]] && LINE2+=" ${DIM}↻$(fmt_eta "$SEVEN_D_ETA")${RESET}"
fi

printf '%s\n%s\n' "$LINE1" "$LINE2"
