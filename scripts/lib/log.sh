#!/usr/bin/env bash
# log.sh — dependency-free terminal logging helpers shared across scripts.
# shellcheck disable=SC2034,SC2329

[ -n "${__DOTFILES_LOG_SH:-}" ] && return 0
__DOTFILES_LOG_SH=1

# Colors emitted only on a TTY; always defined (empty otherwise) for `set -u`.
ui_init_colors() {
    if [ -t 1 ]; then
        BOLD=$'\033[1m'
        DIM=$'\033[2m'
        GREEN=$'\033[32m'
        YELLOW=$'\033[33m'
        BLUE=$'\033[34m'
        RED=$'\033[31m'
        CYAN=$'\033[36m'
        RESET=$'\033[0m'
    else
        BOLD=""
        DIM=""
        GREEN=""
        YELLOW=""
        BLUE=""
        RED=""
        CYAN=""
        RESET=""
    fi
}

# Unicode glyphs when the locale advertises UTF-8, else ASCII to avoid mojibake.
ui_init_glyphs() {
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8* | *utf8* | *UTF8*)
            BAR="│"
            NODE="◆"
            OK_MARK="✓"
            ARROW_MARK="→"
            FAIL_MARK="✗"
            NOTE="•"
            SUB_MARK="↳"
            BAR_FULL="█"
            BAR_EMPTY="░"
            RULE="──"
            BOX_TOP="╭────────────────────────────────────────────────────────────╮"
            BOX_BOTTOM="╰────────────────────────────────────────────────────────────╯"
            ;;
        *)
            BAR="|"
            NODE="*"
            OK_MARK="OK"
            ARROW_MARK=">"
            FAIL_MARK="X"
            NOTE="-"
            SUB_MARK="\\_"
            BAR_FULL="#"
            BAR_EMPTY="-"
            RULE="--"
            BOX_TOP="+------------------------------------------------------------+"
            BOX_BOTTOM="+------------------------------------------------------------+"
            ;;
    esac
}

# Rail-style "│  ✓ message" log helpers (say/ok/info/warn/fail/dim/hr).
ui_init_logging() {
    ui_init_colors
    ui_init_glyphs

    line_prefix() { printf "%s%s%s" "$CYAN" "$BAR" "$RESET"; }
    node_prefix() { printf "%s%s%s" "${ACCENT:-$CYAN}" "$NODE" "$RESET"; }

    say() { printf "%s  %s\n" "$(line_prefix)" "$1"; }
    ok() { printf "%s  %s%s%s %s\n" "$(line_prefix)" "$GREEN" "$OK_MARK" "$RESET" "$1"; }
    info() { printf "%s  %s%s%s %s\n" "$(line_prefix)" "$BLUE" "$ARROW_MARK" "$RESET" "$1"; }
    warn() { printf "%s  %s!%s %s\n" "$(line_prefix)" "$YELLOW" "$RESET" "$1"; }
    fail() { printf "%s  %s%s%s %s\n" "$(line_prefix)" "$RED" "$FAIL_MARK" "$RESET" "$1"; }
    dim() { printf "%s  %s%s%s\n" "$(line_prefix)" "$DIM" "$1" "$RESET"; }
    hr() { printf "%s\n" "$(line_prefix)"; }
}

# Flat status vocabulary (no rail): indent + colored glyph, for report scripts.
ui_init_status() {
    ui_init_colors
    ui_init_glyphs

    s_pass() { printf "  %s%s%s  %s\n" "$GREEN" "$OK_MARK" "$RESET" "$1"; }
    s_warn() { printf "  %s!%s  %s\n" "$YELLOW" "$RESET" "$1"; }
    s_note() { printf "  %s%s%s  %s\n" "$BLUE" "$NOTE" "$RESET" "$1"; }
    s_fail() { printf "  %s%s%s  %s\n" "$RED" "$FAIL_MARK" "$RESET" "$1"; }
    s_info() { printf "  %s%s%s %s\n" "$BLUE" "$ARROW_MARK" "$RESET" "$1"; }
    s_section() { printf "\n%s%s%s %s %s%s\n" "$BOLD" "$BLUE" "$RULE" "$1" "$RULE" "$RESET"; }

    # dim/hr in this vocabulary's flat style, so `explain` works under either
    # initializer and adopts whichever look the calling script chose.
    dim() { printf "  %s%s%s\n" "$DIM" "$1" "$RESET"; }
    hr() { printf "\n"; }
}

# ── Explanations ──────────────────────────────────────────────────────────────
# On by default: this setup is touched a few times a year, so every verb says
# what it is about to do (and what it will never do) before doing it.
# QUIET=1 trims output back to results.

ui_quiet() { [ "${QUIET:-0}" = "1" ]; }

# explain LINE… — dim context lines, suppressed under QUIET=1. Always returns 0
# so a suppressed explain can't trip `set -e` at the end of a function.
explain() {
    ui_quiet && return 0
    local line
    for line in "$@"; do
        if [ -z "$line" ]; then hr; else dim "$line"; fi
    done
    return 0
}

# ── Steps & elapsed time ──────────────────────────────────────────────────────
# Long installs look hung. Numbered steps say where you are; elapsed time on
# anything slow says it was working.

ui_now() { date +%s 2>/dev/null || echo 0; }

# ui_elapsed START — "42s" / "6m12s". Empty for trivially fast steps, so quick
# runs stay clean and only real waits get a number.
ui_elapsed() {
    local start="${1:-0}" now delta
    [ "$start" -gt 0 ] 2>/dev/null || return 0
    now="$(ui_now)"
    delta=$((now - start))
    [ "$delta" -ge 3 ] || return 0
    if [ "$delta" -lt 60 ]; then
        printf '%ds' "$delta"
    else
        printf '%dm%02ds' "$((delta / 60))" "$((delta % 60))"
    fi
}

# ui_init_steps TOTAL — enable step_* helpers for a run of TOTAL steps.
ui_init_steps() {
    ui_init_logging
    UI_STEP_TOTAL="${1:-0}"
    UI_STEP_INDEX=0
    UI_STEP_T0=0

    # step_begin TITLE — "◆  [2/5] Homebrew", blank line above for breathing room.
    step_begin() {
        UI_STEP_INDEX=$((UI_STEP_INDEX + 1))
        UI_STEP_T0="$(ui_now)"
        echo
        printf "%s  %s[%s/%s]%s %s%s%s\n" "$(node_prefix)" \
            "$DIM" "$UI_STEP_INDEX" "$UI_STEP_TOTAL" "$RESET" "$BOLD" "$1" "$RESET"
    }

    # step_ok / step_skip / step_fail — close the current step, timing it when slow.
    step_ok() {
        local t
        t="$(ui_elapsed "$UI_STEP_T0")"
        if [ -n "$t" ]; then
            printf "%s  %s%s%s %s %s(%s)%s\n" "$(line_prefix)" "$GREEN" "$OK_MARK" "$RESET" "$1" "$DIM" "$t" "$RESET"
        else
            ok "$1"
        fi
    }
    step_skip() { dim "$1"; }
    step_fail() { fail "$1"; }
}

# ── Progress ──────────────────────────────────────────────────────────────────
# A bar is only honest when there is a real denominator. These helpers take an
# explicit TOTAL and are ticked once per genuinely-completed item; nothing here
# animates on a timer or interpolates. Where no denominator exists (Apple's GUI
# installer, a single download), use ui_wait_tick instead — elapsed time only.
#
# Counter state lives in a temp file, not a variable: the producer is usually a
# `cmd | while read` pipeline, whose body bash runs in a subshell.

UI_PROGRESS_WIDTH="${UI_PROGRESS_WIDTH:-24}"

# _ui_bar DONE TOTAL — "████████░░░░░░░░". Built by appending, because bash
# substring arithmetic is byte-based and would slice a multi-byte block glyph.
_ui_bar() {
    local done="$1" total="$2" filled i out=""
    [ "$total" -gt 0 ] 2>/dev/null || total=1
    filled=$((done * UI_PROGRESS_WIDTH / total))
    [ "$filled" -gt "$UI_PROGRESS_WIDTH" ] && filled="$UI_PROGRESS_WIDTH"
    [ "$filled" -lt 0 ] && filled=0
    i=0
    while [ "$i" -lt "$filled" ]; do
        out="$out$BAR_FULL"
        i=$((i + 1))
    done
    while [ "$i" -lt "$UI_PROGRESS_WIDTH" ]; do
        out="$out$BAR_EMPTY"
        i=$((i + 1))
    done
    printf '%s' "$out"
}

# ui_progress_start TOTAL [LABEL] — begin a run of TOTAL items.
ui_progress_start() {
    UI_PROGRESS_TOTAL="${1:-0}"
    UI_PROGRESS_LABEL="${2:-}"
    UI_PROGRESS_T0="$(ui_now)"
    UI_PROGRESS_STATE="$(mktemp -t uiprog 2>/dev/null || echo "/tmp/uiprog.$$")"
    printf '0\n' >"$UI_PROGRESS_STATE"
    export UI_PROGRESS_TOTAL UI_PROGRESS_LABEL UI_PROGRESS_T0 UI_PROGRESS_STATE
    ui_progress_render ""
}

ui_progress_count() { cat "$UI_PROGRESS_STATE" 2>/dev/null || echo 0; }

# ui_progress_render ITEM — draw without advancing (e.g. to show a phase change).
ui_progress_render() {
    local item="${1:-}" done total pct t line
    done="$(ui_progress_count)"
    total="${UI_PROGRESS_TOTAL:-0}"
    [ "$total" -gt 0 ] 2>/dev/null || total=1
    pct=$((done * 100 / total))
    t="$(ui_elapsed "${UI_PROGRESS_T0:-0}")"
    if [ ! -t 1 ]; then
        # No terminal: one plain line per item, so CI logs stay readable. Only
        # on a *change* — the caller also redraws on a timer to keep the elapsed
        # clock moving, which without this printed the same line once a second.
        if [ -n "$item" ] && [ "$done|$item" != "${UI_PROGRESS_LAST:-}" ]; then
            UI_PROGRESS_LAST="$done|$item"
            printf '  [%d/%d] %s\n' "$done" "$total" "$item"
        fi
        return 0
    fi
    line="$(printf '%s  %s %s%3d%%%s  %s%d/%d%s' \
        "$(line_prefix)" "$(_ui_bar "$done" "$total")" \
        "$BOLD" "$pct" "$RESET" "$DIM" "$done" "$total" "$RESET")"
    [ -n "$t" ] && line="$line $(printf '%s%s%s' "$DIM" "$t" "$RESET")"
    [ -n "$item" ] && line="$line  $(printf '%s%s%s' "$DIM" "$item" "$RESET")"
    printf '\r\033[K%s' "$line"
}

# ui_progress_tick ITEM — one item finished; advance and redraw.
ui_progress_tick() {
    local n
    n="$(($(ui_progress_count) + 1))"
    printf '%s\n' "$n" >"$UI_PROGRESS_STATE"
    ui_progress_render "${1:-}"
}

# ui_progress_pause MSG — clear the bar and leave MSG behind as a settled line,
# so the cursor ends up on a *fresh* line the caller will not repaint.
#
# This exists for one failure mode: a child process (a Homebrew cask, say) can
# write a `sudo` password prompt straight to /dev/tty, which the next
# `\r\033[K` redraw erases. The result looks exactly like a hang — an install
# sitting at the same count for minutes with nothing on screen to explain it.
# A caller that has gone quiet parks the bar here and stops rendering; whatever
# prompt arrives next survives, because nothing is overwriting that line.
#
# The counter is untouched, so ui_progress_render/_tick resume cleanly.
ui_progress_pause() {
    [ -t 1 ] && printf '\r\033[K'
    [ -n "${1:-}" ] && dim "$1"
    return 0
}

# ui_progress_finish MSG — clear the bar and leave one settled line behind.
ui_progress_finish() {
    local done total t
    done="$(ui_progress_count)"
    total="${UI_PROGRESS_TOTAL:-0}"
    t="$(ui_elapsed "${UI_PROGRESS_T0:-0}")"
    [ -t 1 ] && printf '\r\033[K'
    rm -f "$UI_PROGRESS_STATE" 2>/dev/null || true
    if [ -n "${1:-}" ]; then
        if [ -n "$t" ]; then
            printf '%s  %s%s%s %s %s(%d/%d in %s)%s\n' "$(line_prefix)" \
                "$GREEN" "$OK_MARK" "$RESET" "$1" "$DIM" "$done" "$total" "$t" "$RESET"
        else
            ok "$1 ($done/$total)"
        fi
    fi
    unset UI_PROGRESS_STATE UI_PROGRESS_TOTAL UI_PROGRESS_T0 UI_PROGRESS_LABEL
}

# ui_wait_tick START MSG — for work with no denominator: elapsed time only, on a
# single rewritten line. Deliberately not a bar; there is nothing to measure.
ui_wait_tick() {
    local start="$1" msg="${2:-working}" delta
    [ -t 1 ] || return 0
    delta=$(($(ui_now) - start))
    printf '\r\033[K%s  %s%s… %dm%02ds%s' "$(line_prefix)" "$DIM" "$msg" \
        "$((delta / 60))" "$((delta % 60))" "$RESET"
}
ui_wait_clear() {
    [ -t 1 ] && printf '\r\033[K'
    return 0
}
