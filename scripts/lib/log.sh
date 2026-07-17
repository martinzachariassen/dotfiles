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
}
