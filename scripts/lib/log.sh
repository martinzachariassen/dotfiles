#!/usr/bin/env bash
# log.sh — tiny, dependency-free terminal logging helpers shared across scripts.
#
# Sourced by doctor.sh, bootstrap-auth.sh, setup-ollama.sh, chezup.sh, and the
# obsidian apply hook. Kept dependency-free so it behaves identically on a fresh
# machine before any package is installed.
#
# Three idempotent entry points:
#   ui_init_colors  — populate BOLD/DIM/GREEN/YELLOW/BLUE/RED/CYAN/RESET
#   ui_init_glyphs  — BAR/NODE/OK_MARK/ARROW_MARK/FAIL_MARK/NOTE/RULE + box glyphs
#   ui_init_logging — the rail-style log helpers (line_prefix/node_prefix/
#                     say/ok/info/warn/fail/dim/hr); inits colors + glyphs first
#
# Callers consume the color/glyph vars and the helper functions, so their use
# isn't visible in this file. Suppress the false-positive unused/unreached
# warnings. (V1 had a 430-line "wizard" superset here for install.sh + chezup;
# the bootstrap is now a plain hand-written script and chezup uses the light
# logging helpers, so the wizard is gone.)
# shellcheck disable=SC2034,SC2329

# Source guard so re-sourcing is cheap and safe.
[ -n "${__DOTFILES_LOG_SH:-}" ] && return 0
__DOTFILES_LOG_SH=1

# ui_init_colors — define BOLD DIM GREEN YELLOW BLUE RED CYAN RESET.
# Colors are emitted only when stdout is a terminal, so piped/CI output stays
# plain. Variables are always defined (empty when not a TTY) so callers can use
# them unconditionally under `set -u`.
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

# ui_init_glyphs — define BAR NODE OK_MARK ARROW_MARK FAIL_MARK NOTE RULE
# BOX_TOP BOX_BOTTOM. Uses Unicode line-drawing when the locale advertises
# UTF-8, otherwise falls back to ASCII so the output never turns into mojibake
# on a bare C/POSIX locale.
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

# ui_init_logging — define the shared rail-style log helpers as globals:
#   line_prefix node_prefix say ok info warn fail dim hr
# The "│  ✓ message" vocabulary. Initialises colors + glyphs first (both
# idempotent) so a caller can just `ui_init_logging` and go.
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
