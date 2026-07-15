#!/usr/bin/env bash
# Claude Code status line: model + cwd + git branch/status + PR badge on line
# one, a color-coded context-usage bar with session cost/duration on line two.
set -euo pipefail

input="$(cat)"

MODEL="$(jq -r '.model.display_name' <<<"$input")"
DIR="$(jq -r '.workspace.current_dir' <<<"$input")"
SESSION_ID="$(jq -r '.session_id' <<<"$input")"
COST="$(jq -r '.cost.total_cost_usd // 0' <<<"$input")"
DURATION_MS="$(jq -r '.cost.total_duration_ms // 0' <<<"$input")"
PCT="$(jq -r '.context_window.used_percentage // 0' <<<"$input" | cut -d. -f1)"
PR_NUMBER="$(jq -r '.pr.number // empty' <<<"$input")"

CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

# --- git branch/status, cached per session so we don't shell out to git on
# every debounced refresh (session_id is stable for the session's lifetime
# and unique across concurrent sessions, unlike a PID). ---
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
        BRANCH="$(git -C "$DIR" branch --show-current 2>/dev/null)"
        STAGED="$(git -C "$DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')"
        MODIFIED="$(git -C "$DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')"
        printf '%s|%s|%s\n' "$BRANCH" "$STAGED" "$MODIFIED" >"$CACHE_FILE"
    else
        printf '||\n' >"$CACHE_FILE"
    fi
fi
IFS='|' read -r BRANCH STAGED MODIFIED <"$CACHE_FILE"

GIT_SEGMENT=""
if [[ -n "$BRANCH" ]]; then
    GIT_SEGMENT=" | 🌿 ${BRANCH}"
    ((STAGED > 0)) && GIT_SEGMENT+=" ${GREEN}+${STAGED}${RESET}"
    ((MODIFIED > 0)) && GIT_SEGMENT+=" ${YELLOW}~${MODIFIED}${RESET}"
fi

PR_SEGMENT=""
[[ -n "$PR_NUMBER" ]] && PR_SEGMENT=" | PR #${PR_NUMBER}"

# --- context usage bar, threshold-colored ---
if ((PCT >= 90)); then
    BAR_COLOR="$RED"
elif ((PCT >= 70)); then
    BAR_COLOR="$YELLOW"
else
    BAR_COLOR="$GREEN"
fi

FILLED=$((PCT / 10))
EMPTY=$((10 - FILLED))
BAR=""
if ((FILLED > 0)); then
    printf -v FILL '%*s' "$FILLED" ''
    BAR="${FILL// /█}"
fi
if ((EMPTY > 0)); then
    printf -v PAD '%*s' "$EMPTY" ''
    BAR="${BAR}${PAD// /░}"
fi

COST_FMT="$(printf '$%.2f' "$COST")"
DURATION_SEC=$((DURATION_MS / 1000))
MINS=$((DURATION_SEC / 60))
SECS=$((DURATION_SEC % 60))

printf '%s[%s]%s 📁 %s%s%s\n' "$CYAN" "$MODEL" "$RESET" "${DIR##*/}" "$GIT_SEGMENT" "$PR_SEGMENT"
printf '%s%s%s %s%% | %s | ⏱️ %sm %ss\n' "$BAR_COLOR" "$BAR" "$RESET" "$PCT" "$COST_FMT" "$MINS" "$SECS"
