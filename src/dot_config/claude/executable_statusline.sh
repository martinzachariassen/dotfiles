#!/usr/bin/env bash
# Claude Code status line.
#   Line 1 — identity: model + mode flags · dir · git (with diff tally) · PR
#   Line 2 — budget: context gauge · cost + burn rate · api/wall time · quota + reset countdowns
#
# Icons are Nerd Font glyphs, matching the vocabulary starship already uses in the
# prompt directly above. Every glyph occupies exactly one cell, which is what lets
# the width budget below measure segments with plain ${#var}.
#
# Colors are ANSI 16 plus attributes only — no hardcoded hex. The terminal theme
# (catppuccin-frappe) maps those onto the palette, so the bar follows a theme
# switch instead of drifting off it.
#
# Written for bash 3.2 (macOS system bash).
set -euo pipefail

# The width budget measures segments with ${#var}, which counts characters only
# under a UTF-8 ctype; a C locale counts bytes and reads every glyph as three or
# four cells. Probe with a two-byte character rather than trusting the locale name:
# macOS spells the charset-only locale "UTF-8" and glibc spells it "C.UTF-8", and
# assigning one the system lacks makes bash warn on stderr — which the host would
# render as a third status line.
UTF8_PROBE='é'
if ((${#UTF8_PROBE} != 1)); then
    for loc in C.UTF-8 UTF-8 en_US.UTF-8; do
        { export LC_CTYPE="$loc"; } 2>/dev/null
        ((${#UTF8_PROBE} == 1)) && break
    done
fi
# Still counting bytes means no width is trustworthy, so the budget is stood down
# entirely — an unbudgeted line that wraps beats one shredded by bogus arithmetic.
UTF8_OK=1
((${#UTF8_PROBE} == 1)) || UTF8_OK=0

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
TRACK=$'\033[90m' # bright black — the gauge's unfilled run
SEP=" ${DIM}·${RESET} "
SEP_WIDTH=3

# --- icons (Nerd Font 3.x; each is one cell and always followed by one space) ---
I_DIR=$''      # fa-folder
I_BRANCH=$''   # pl-branch — the same glyph starship's git_branch uses
I_WORKTREE=$'' # oct-repo_forked
I_TAG=$''      # fa-tag
I_PR=$''       # oct-git_pull_request
I_DIFF=$''     # oct-diff — marks session edits, so +N stays unambiguous
I_AGENT=$'󰚩'    # md-robot
I_BRAIN=$'󰧑'    # md-brain
I_BOLT=$''     # fa-bolt
I_CTX=$'󰍛'      # md-memory
I_CLOCK=$''    # fa-clock
I_RESET=$''    # fa-refresh
I_OK=$''       # fa-check
I_NO=$''       # fa-times

# --- helpers ---

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

# One threshold rule for every percentage on the bar — context, 5h and 7d alike.
# A shared rule means "yellow" carries the same weight wherever it appears.
pct_color() {
    if (($1 >= 90)); then
        printf '%s' "$RED"
    elif (($1 >= 70)); then
        printf '%s' "$YELLOW"
    else
        printf '%s' "$GREEN"
    fi
}

# Plain uppercase ASCII — small-caps Unicode isn't in every font's cmap and
# falls back to a mismatched font, which stands out next to the model name.
effort_label() {
    case "$1" in
        low) printf 'LOW' ;;
        medium) printf 'MED' ;;
        high) printf 'HIGH' ;;
        xhigh) printf 'XHIGH' ;;
        max) printf 'MAX' ;;
        *) printf '%s' "$1" ;;
    esac
}

# Clip an untrusted-length string, reserving a cell for the ellipsis.
trunc() {
    local max=$1 s=$2
    if ((${#s} > max)); then printf '%s…' "${s:0:max-1}"; else printf '%s' "$s"; fi
}

# Wrap text in an OSC 8 hyperlink (Cmd/Ctrl-click in supporting terminals).
osc8() { printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$1" "$2"; }

# The payload carries no terminal width, so fall back through the environment and
# finally to 0, which the budget treats as "unlimited" rather than guessing wrong.
term_cols() {
    local c="${COLUMNS:-}"
    if [[ "$c" =~ ^[0-9]+$ ]] && ((c > 0)); then
        printf '%s' "$c"
        return
    fi
    c="$(tput cols 2>/dev/null </dev/tty || true)"
    if [[ "$c" =~ ^[0-9]+$ ]] && ((c > 0)); then
        printf '%s' "$c"
        return
    fi
    printf '0'
}

# --- segment assembly ---
# Parallel arrays because bash 3.2 has no associative arrays. Each segment carries
# its rendered text, the plain text it measures as, and a drop priority: 0 never
# drops, higher numbers drop first once the line overruns its budget.
SEG_TEXT=() SEG_PLAIN=() SEG_PRIO=()

seg() { # seg <priority> <plain> <rendered>
    SEG_PRIO+=("$1")
    SEG_PLAIN+=("$2")
    SEG_TEXT+=("$3")
}

seg_reset() { SEG_TEXT=() SEG_PLAIN=() SEG_PRIO=(); }

# Join the segments, shedding the least important ones until the line fits.
fit_line() {
    local budget=$1 n=${#SEG_TEXT[@]} i prio total=0
    ((n == 0)) && return 0

    local keep=()
    for ((i = 0; i < n; i++)); do
        keep[i]=1
        total=$((total + ${#SEG_PLAIN[i]}))
    done
    total=$((total + (n - 1) * SEP_WIDTH))

    if ((budget > 0)); then
        # Walk priorities from least to most important; within a priority drop the
        # rightmost segment first, so what survives keeps its reading order.
        for ((prio = 9; prio >= 1; prio--)); do
            for ((i = n - 1; i >= 0; i--)); do
                ((total <= budget)) && break 2
                if ((keep[i] == 1 && SEG_PRIO[i] == prio)); then
                    keep[i]=0
                    total=$((total - ${#SEG_PLAIN[i]} - SEP_WIDTH))
                fi
            done
        done
    fi

    local out="" first=1
    for ((i = 0; i < n; i++)); do
        ((keep[i] == 0)) && continue
        if ((first == 1)); then
            out="${SEG_TEXT[i]}"
            first=0
        else
            out+="${SEP}${SEG_TEXT[i]}"
        fi
    done
    printf '%s' "$out"
}

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
    ] | join("")' <<<"$input")"

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

# Two columns of slack: the host pads the bar, and a line that exactly fills the
# width still wraps in some terminals.
COLS="$(term_cols)"
BUDGET=0
((UTF8_OK == 1 && COLS > 0)) && BUDGET=$((COLS - 2))

# --- git state, cached per session ---
CACHE_FILE="${TMPDIR:-/tmp}/claude-statusline-git-${SESSION_ID}"
CACHE_MAX_AGE=5

cache_is_stale() {
    [[ ! -f "$CACHE_FILE" ]] && return 0
    local mtime age
    # BSD stat first (this is a macOS setup), GNU second. The result is range-checked
    # rather than trusted: GNU stat accepts -f as --file-system and answers %m with a
    # mount point, so a plain || chain would silently feed "/" to the arithmetic below.
    mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || true)
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || true)
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
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
# quiet until something is actually worth knowing. They ride along with the model
# segment, which never drops — each is a couple of cells at most.
seg_reset

M_PLAIN="$MODEL" M_TEXT="${CYAN}${BOLD}${MODEL}${RESET}"
if [[ -n "$EFFORT" ]]; then
    E="$(effort_label "$EFFORT")"
    M_PLAIN+=" $E" M_TEXT+=" ${DIM}${E}${RESET}"
fi
if [[ -n "$FAST_MODE" ]]; then
    M_PLAIN+=" $I_BOLT" M_TEXT+=" ${YELLOW}${I_BOLT}${RESET}"
fi
if [[ -n "$BIG_CTX" ]]; then # past 200k: premium-tier pricing
    M_PLAIN+=" 1M" M_TEXT+=" ${YELLOW}1M${RESET}"
fi
if [[ -n "$NO_THINKING" ]]; then
    M_PLAIN+=" $I_BRAIN off" M_TEXT+=" ${DIM}${I_BRAIN} off${RESET}"
fi
if [[ -n "$VIM_MODE" && "$VIM_MODE" != "INSERT" ]]; then
    M_PLAIN+=" $VIM_MODE" M_TEXT+=" ${MAGENTA}${VIM_MODE}${RESET}"
fi
seg 0 "$M_PLAIN" "$M_TEXT"

if [[ -n "$AGENT_NAME" ]]; then
    A="$(trunc 16 "$AGENT_NAME")"
    seg 5 "$I_AGENT $A" "${DIM}${I_AGENT} ${A}${RESET}"
fi
if [[ -n "$OUTPUT_STYLE" && "$OUTPUT_STYLE" != "default" ]]; then
    O="$(trunc 16 "$OUTPUT_STYLE")"
    seg 7 "$O" "${DIM}${O}${RESET}"
fi

D="$(trunc 24 "${DIR##*/}")"
D_PLAIN="$I_DIR $D" D_TEXT="${DIM}${I_DIR}${RESET} ${BLUE}${BOLD}${D}${RESET}"
if ((ADDED_DIRS > 0)); then
    D_PLAIN+=" +${ADDED_DIRS}dir" D_TEXT+=" ${DIM}+${ADDED_DIRS}dir${RESET}"
fi
seg 0 "$D_PLAIN" "$D_TEXT"

if [[ -n "$SESSION_NAME" ]]; then
    S="$(trunc 28 "$SESSION_NAME")"
    seg 4 "$I_TAG $S" "${DIM}${I_TAG} ${S}${RESET}"
fi

# Git counts use starship's notation so the same symbol means the same thing in
# the prompt and the bar: +staged !modified ?untracked ✗conflict ⇡ahead ⇣behind.
if [[ -n "$BRANCH" ]]; then
    B="$(trunc 32 "$BRANCH")"
    G_PLAIN="$I_BRANCH $B" G_TEXT="${DIM}${I_BRANCH}${RESET} ${MAGENTA}${B}${RESET}"
    ((STAGED > 0)) && G_PLAIN+=" +$STAGED" && G_TEXT+=" ${GREEN}+${STAGED}${RESET}"
    ((MODIFIED > 0)) && G_PLAIN+=" !$MODIFIED" && G_TEXT+=" ${YELLOW}!${MODIFIED}${RESET}"
    ((UNTRACKED > 0)) && G_PLAIN+=" ?$UNTRACKED" && G_TEXT+=" ${BLUE}?${UNTRACKED}${RESET}"
    ((CONFLICTS > 0)) && G_PLAIN+=" ✗$CONFLICTS" && G_TEXT+=" ${RED}✗${CONFLICTS}${RESET}"
    ((AHEAD > 0)) && G_PLAIN+=" ⇡$AHEAD" && G_TEXT+=" ${CYAN}⇡${AHEAD}${RESET}"
    ((BEHIND > 0)) && G_PLAIN+=" ⇣$BEHIND" && G_TEXT+=" ${CYAN}⇣${BEHIND}${RESET}"
    seg 0 "$G_PLAIN" "$G_TEXT"
fi

if [[ -n "$WORKTREE" ]]; then
    W="$(trunc 20 "$WORKTREE")"
    seg 3 "$I_WORKTREE $W" "${DIM}${I_WORKTREE} ${W}${RESET}"
fi

# Session edits carry their own icon: without it, "+120" sits next to git's "+3"
# meaning something entirely different.
if ((LINES_ADDED > 0 || LINES_REMOVED > 0)); then
    seg 2 "$I_DIFF +$LINES_ADDED/-$LINES_REMOVED" \
        "${DIM}${I_DIFF}${RESET} ${GREEN}+${LINES_ADDED}${RESET}${DIM}/${RESET}${RED}-${LINES_REMOVED}${RESET}"
fi

if [[ -n "$PR_NUMBER" ]]; then
    case "$PR_STATE" in
        approved) PR_PLAIN="$I_OK #$PR_NUMBER" PR_TEXT="${GREEN}${I_OK} #${PR_NUMBER}${RESET}" ;;
        changes_requested) PR_PLAIN="$I_NO #$PR_NUMBER" PR_TEXT="${RED}${I_NO} #${PR_NUMBER}${RESET}" ;;
        draft) PR_PLAIN="$I_PR #$PR_NUMBER draft" PR_TEXT="${DIM}${I_PR} #${PR_NUMBER} draft${RESET}" ;;
        *) PR_PLAIN="$I_PR #$PR_NUMBER" PR_TEXT="${YELLOW}${I_PR} #${PR_NUMBER}${RESET}" ;;
    esac
    [[ -n "$PR_URL" ]] && PR_TEXT="$(osc8 "$PR_URL" "$PR_TEXT")"
    seg 1 "$PR_PLAIN" "$PR_TEXT"
fi

LINE1="$(fit_line "$BUDGET")"

# ============================ line 2: budget ============================
seg_reset

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
BAR_COLOR="$(pct_color "$PCT")"

# The gauge and its token count are one reading, and so are the cost and its burn
# rate. Keeping each pair inside a single segment costs 3 cells less than a "·"
# join and stops the eye from parsing them as unrelated facts.
X_PLAIN="$I_CTX ${FILLED_STR}${EMPTY_STR} ${PCT}%"
X_TEXT="${DIM}${I_CTX}${RESET} ${BAR_COLOR}${FILLED_STR}${RESET}${TRACK}${EMPTY_STR}${RESET} ${BAR_COLOR}${PCT}%${RESET}"
if ((CTX_SIZE > 0)); then
    T="$(fmt_tokens "$USED_TOKENS")/$(fmt_tokens "$CTX_SIZE")"
    X_PLAIN+=" $T" X_TEXT+=" ${DIM}${T}${RESET}"
fi
seg 0 "$X_PLAIN" "$X_TEXT"

# The "$" in the amount is the icon — a money glyph in front of it would say it twice.
C="$(printf '$%.2f' "$COST")"
C_PLAIN="$C" C_TEXT="${YELLOW}${C}${RESET}"
# Burn rate stays hidden for the first two minutes, where it is pure noise.
if [[ -n "$RATE" ]]; then
    R="$(printf '$%.2f/h' "$RATE")"
    C_PLAIN+=" $R" C_TEXT+=" ${DIM}${R}${RESET}"
fi
seg 0 "$C_PLAIN" "$C_TEXT"

# api/wall separates "waiting on the model" from "session has been open".
CLK="$(fmt_dur $((API_MS / 1000)))/$(fmt_dur $((DURATION_MS / 1000)))"
seg 5 "$I_CLOCK $CLK" "${DIM}${I_CLOCK} ${CLK}${RESET}"

# Quota percentage answers "how much is left", the countdown answers "for how long" —
# neither is actionable without the other.
if [[ -n "$FIVE_H" ]]; then
    Q_PLAIN="5h ${FIVE_H}%" Q_TEXT="5h $(pct_color "$FIVE_H")${FIVE_H}%${RESET}"
    if [[ -n "$FIVE_H_ETA" ]]; then
        E="$(fmt_eta "$FIVE_H_ETA")"
        Q_PLAIN+=" $I_RESET $E" Q_TEXT+=" ${DIM}${I_RESET} ${E}${RESET}"
    fi
    seg 1 "$Q_PLAIN" "$Q_TEXT"
fi
if [[ -n "$SEVEN_D" ]]; then
    Q_PLAIN="7d ${SEVEN_D}%" Q_TEXT="7d $(pct_color "$SEVEN_D")${SEVEN_D}%${RESET}"
    if [[ -n "$SEVEN_D_ETA" ]]; then
        E="$(fmt_eta "$SEVEN_D_ETA")"
        Q_PLAIN+=" $I_RESET $E" Q_TEXT+=" ${DIM}${I_RESET} ${E}${RESET}"
    fi
    seg 2 "$Q_PLAIN" "$Q_TEXT"
fi

LINE2="$(fit_line "$BUDGET")"

printf '%s\n%s\n' "$LINE1" "$LINE2"
