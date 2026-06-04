#!/usr/bin/env bash
# ui.sh — tiny terminal UI helpers shared across scripts.
#
# Sourced by doctor.sh, bootstrap-auth.sh, and setup-ollama.sh. Kept
# dependency-free so it behaves identically on a fresh machine before every
# package is installed.
#
# Two entry points, both idempotent:
#   ui_init_colors  — populate ANSI color vars (empty when stdout isn't a TTY)
#   ui_init_glyphs  — populate Unicode/ASCII box + status glyphs
#
# The color/glyph vars are consumed by callers that source this file, so their
# use isn't visible here. Suppress the false-positive unused-variable warnings.
# shellcheck disable=SC2034

# Source guard so re-sourcing is cheap and safe.
[ -n "${__DOTFILES_UI_SH:-}" ] && return 0
__DOTFILES_UI_SH=1

# ui_init_colors — define BOLD DIM GREEN YELLOW BLUE RED CYAN RESET.
# Colors are emitted only when stdout is a terminal, so piped/CI output stays
# plain. Variables are always defined (empty when not a TTY) so callers can use
# them unconditionally under `set -u`.
ui_init_colors() {
    if [ -t 1 ]; then
        BOLD=$'\033[1m'; DIM=$'\033[2m'
        GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'
        RED=$'\033[31m'; CYAN=$'\033[36m'
        RESET=$'\033[0m'
    else
        BOLD=""; DIM=""
        GREEN=""; YELLOW=""; BLUE=""
        RED=""; CYAN=""
        RESET=""
    fi
}

# ui_init_glyphs — define BAR NODE OK_MARK ARROW_MARK FAIL_MARK BOX_TOP
# BOX_BOTTOM. Uses Unicode line-drawing when the locale advertises UTF-8,
# otherwise falls back to ASCII so the output never turns into mojibake on a
# bare C/POSIX locale.
ui_init_glyphs() {
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8*|*utf8*|*UTF8*)
            BAR="│"; NODE="◆"; OK_MARK="✓"; ARROW_MARK="→"; FAIL_MARK="✗"
            BOX_TOP="╭────────────────────────────────────────────────────────────╮"
            BOX_BOTTOM="╰────────────────────────────────────────────────────────────╯"
            ;;
        *)
            BAR="|"; NODE="*"; OK_MARK="OK"; ARROW_MARK=">"; FAIL_MARK="X"
            BOX_TOP="+------------------------------------------------------------+"
            BOX_BOTTOM="+------------------------------------------------------------+"
            ;;
    esac
}
