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
