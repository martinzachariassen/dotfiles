#!/usr/bin/env bash
# ui.sh — tiny terminal UI helpers shared across scripts.
#
# Sourced by doctor.sh, bootstrap-auth.sh, setup-ollama.sh, and chezup.sh. Kept
# dependency-free so it behaves identically on a fresh machine before every
# package is installed.
#
# Three entry points, all idempotent:
#   ui_init_colors  — populate BOLD/DIM/GREEN/YELLOW/BLUE/RED/CYAN/RESET
#   ui_init_glyphs  — populate basic BAR/NODE/OK_MARK/ARROW_MARK/FAIL_MARK + box
#   ui_init_wizard  — superset: depth-aware themed palette + rich glyphs + the
#                     phase/setting/banner/prompt helpers used by install.sh,
#                     so chezup feels like the install wizard
#
# The color/glyph vars and the wizard helper functions are consumed by callers
# that source this file, so their use isn't visible here. Suppress the
# false-positive unused-variable and unreached-function warnings.
# shellcheck disable=SC2034,SC2329

# Source guard so re-sourcing is cheap and safe.
[ -n "${__DOTFILES_UI_SH:-}" ] && return 0
__DOTFILES_UI_SH=1

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

# ui_init_glyphs — define BAR NODE OK_MARK ARROW_MARK FAIL_MARK BOX_TOP
# BOX_BOTTOM. Uses Unicode line-drawing when the locale advertises UTF-8,
# otherwise falls back to ASCII so the output never turns into mojibake on a
# bare C/POSIX locale.
ui_init_glyphs() {
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8* | *utf8* | *UTF8*)
            BAR="│"
            NODE="◆"
            OK_MARK="✓"
            ARROW_MARK="→"
            FAIL_MARK="✗"
            BOX_TOP="╭────────────────────────────────────────────────────────────╮"
            BOX_BOTTOM="╰────────────────────────────────────────────────────────────╯"
            ;;
        *)
            BAR="|"
            NODE="*"
            OK_MARK="OK"
            ARROW_MARK=">"
            FAIL_MARK="X"
            BOX_TOP="+------------------------------------------------------------+"
            BOX_BOTTOM="+------------------------------------------------------------+"
            ;;
    esac
}

# ─── Wizard mode ─────────────────────────────────────────────────────────────
# `ui_init_wizard` brings the rich install.sh look: depth-aware Catppuccin
# Frappé palette, extended glyphs (pointer/spinner/progress/box), and the
# phase/setting/banner/prompt helpers as global functions (say, ok, info,
# warn, fail, dim, hr, rule, setting, phase_open, phase_close, ui_banner,
# prompt_confirm, prompt_choice, …). chezup.sh opts in; doctor.sh / bootstrap-
# auth.sh keep using the minimal `ui_init_colors` + `ui_init_glyphs` they
# already source today.
#
# Per docs/lifecycle.md (`One engine, one look`), the wizard's terminal styling
# is mirrored here so any script in the repo gets the same vocabulary as
# install.sh. install.sh itself stays self-contained — it's downloaded via
# `curl | bash` before this file exists on disk, so it can't source us. Keep
# the two visual contracts in sync when you change either.

ui_init_wizard() {
    ui_init_colors
    ui_init_glyphs
    _ui_wizard_capabilities
    _ui_wizard_palette
    _ui_wizard_glyphs
    _ui_wizard_define_helpers
}

# Detect color depth, unicode, tty width, raw-mode availability. Mirrors
# install.sh's top-of-file capability probe so the look matches.
_ui_wizard_capabilities() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
        UI_COLOR=1
    else
        UI_COLOR=0
    fi

    UI_DEPTH=16
    case "${COLORTERM:-}" in
        *truecolor* | *24bit*) UI_DEPTH=true ;;
    esac
    if [ "$UI_DEPTH" = 16 ]; then
        case "${TERM:-}" in
            *256color* | *-direct*) UI_DEPTH=256 ;;
        esac
    fi
    [ "$UI_COLOR" = 0 ] && UI_DEPTH=none

    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8* | *utf8* | *UTF8*) UI_UNICODE=1 ;;
        *) UI_UNICODE=0 ;;
    esac

    UI_COLS="$({ tput cols; } 2>/dev/null </dev/tty || true)"
    [ -z "$UI_COLS" ] && UI_COLS="${COLUMNS:-}"
    case "$UI_COLS" in '' | *[!0-9]*) UI_COLS=60 ;; esac
    [ "$UI_COLS" -lt 48 ] && UI_COLS=48
    [ "$UI_COLS" -gt 80 ] && UI_COLS=80

    if [ "${ASSUME_YES:-0}" != "1" ] &&
        command -v stty >/dev/null 2>&1 &&
        (exec </dev/tty >/dev/tty) 2>/dev/null; then
        UI_RAW=1
    else
        UI_RAW=0
    fi
    UI_STTY_SAVED=""
}

# Catppuccin Frappé palette with 256/16 fallbacks. Mirrors install.sh `fg()`.
fg() {
    [ "${UI_COLOR:-0}" = 0 ] && return 0
    case "${UI_DEPTH:-none}" in
        true)
            case "$1" in
                accent) printf '\033[38;2;202;158;230m' ;;
                accent2) printf '\033[38;2;140;170;238m' ;;
                ok) printf '\033[38;2;166;209;137m' ;;
                warn) printf '\033[38;2;229;200;144m' ;;
                err) printf '\033[38;2;231;130;132m' ;;
                info) printf '\033[38;2;153;209;219m' ;;
                muted) printf '\033[38;2;115;121;148m' ;;
                rail) printf '\033[38;2;98;104;128m' ;;
            esac
            ;;
        256)
            case "$1" in
                accent) printf '\033[38;5;183m' ;;
                accent2) printf '\033[38;5;111m' ;;
                ok) printf '\033[38;5;150m' ;;
                warn) printf '\033[38;5;180m' ;;
                err) printf '\033[38;5;210m' ;;
                info) printf '\033[38;5;152m' ;;
                muted) printf '\033[38;5;102m' ;;
                rail) printf '\033[38;5;60m' ;;
            esac
            ;;
        *)
            case "$1" in
                accent) printf '\033[35m' ;;
                accent2) printf '\033[34m' ;;
                ok) printf '\033[32m' ;;
                warn) printf '\033[33m' ;;
                err) printf '\033[31m' ;;
                info) printf '\033[36m' ;;
                muted) printf '\033[90m' ;;
                rail) printf '\033[36m' ;;
            esac
            ;;
    esac
}

# Override the plain palette set by ui_init_colors with the themed one. Keeps
# the same variable names so existing helpers (and any future ones that just
# want a "warning yellow") keep working.
_ui_wizard_palette() {
    if [ "$UI_COLOR" = 1 ]; then
        BOLD=$'\033[1m'
        DIM=$'\033[2m'
        RESET=$'\033[0m'
        GREEN="$(fg ok)"
        YELLOW="$(fg warn)"
        BLUE="$(fg accent2)"
        RED="$(fg err)"
        CYAN="$(fg rail)"
        ACCENT="$(fg accent)"
        INFOC="$(fg info)"
        MUTED="$(fg muted)"
    else
        BOLD=""
        DIM=""
        RESET=""
        GREEN=""
        YELLOW=""
        BLUE=""
        RED=""
        CYAN=""
        ACCENT=""
        INFOC=""
        MUTED=""
    fi
}

# Extended glyph set: pointer/off for menus, progress segments, box-drawing,
# spinner frames. Replaces the basic BOX_TOP/BOX_BOTTOM strings from
# ui_init_glyphs with per-char primitives we compose at render time.
_ui_wizard_glyphs() {
    if [ "$UI_UNICODE" = 1 ]; then
        BAR="│"
        NODE="◆"
        OK_MARK="✓"
        ARROW_MARK="→"
        FAIL_MARK="✗"
        G_POINTER="❯"
        G_OFF="○"
        G_FULL="▰"
        G_EMPTY="▱"
        BOX_TL="╭"
        BOX_TR="╮"
        BOX_BL="╰"
        BOX_BR="╯"
        BOX_H="─"
        BOX_V="│"
        SPIN_FRAMES="⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"
    else
        BAR="|"
        NODE="*"
        OK_MARK="OK"
        ARROW_MARK=">"
        FAIL_MARK="X"
        G_POINTER=">"
        G_OFF="o"
        G_FULL="#"
        G_EMPTY="-"
        BOX_TL="+"
        BOX_TR="+"
        BOX_BL="+"
        BOX_BR="+"
        BOX_H="-"
        BOX_V="|"
        SPIN_FRAMES="| / - \\"
    fi
}

# Define the unprefixed helper functions as globals. Called once by
# ui_init_wizard; safe to call again (re-defines with the same body).
_ui_wizard_define_helpers() {

    # repeat CHAR COUNT — echo CHAR repeated COUNT times (multibyte-safe).
    repeat() {
        local ch="$1" n="$2" out="" i=0
        while [ "$i" -lt "$n" ]; do
            out="$out$ch"
            i=$((i + 1))
        done
        printf '%s' "$out"
    }

    line_prefix() { printf "%s%s%s" "$CYAN" "$BAR" "$RESET"; }
    node_prefix() { printf "%s%s%s" "$ACCENT" "$NODE" "$RESET"; }

    say() { printf "%s  %s\n" "$(line_prefix)" "$1"; }
    ok() { printf "%s  %s%s%s %s\n" "$(line_prefix)" "$GREEN" "$OK_MARK" "$RESET" "$1"; }
    info() { printf "%s  %s%s%s %s\n" "$(line_prefix)" "$BLUE" "$ARROW_MARK" "$RESET" "$1"; }
    warn() { printf "%s  %s!%s %s\n" "$(line_prefix)" "$YELLOW" "$RESET" "$1"; }
    fail() { printf "%s  %s%s%s %s\n" "$(line_prefix)" "$RED" "$FAIL_MARK" "$RESET" "$1"; }
    dim() { printf "%s  %s%s%s\n" "$(line_prefix)" "$DIM" "$1" "$RESET"; }
    hr() { printf "%s\n" "$(line_prefix)"; }

    setting() {
        local label="$1" value="$2"
        printf "%s    %-18s %s\n" "$(line_prefix)" "$label" "$value"
    }

    bool_label() {
        case "${1:-false}" in
            true | 1 | yes) printf 'yes' ;;
            *) printf 'no' ;;
        esac
    }

    rule() {
        printf "%s  %s%s%s\n" "$(line_prefix)" "$MUTED" "$(repeat "$BOX_H" $((UI_COLS - 6)))" "$RESET"
    }

    # progress_bar N M — render "▰▰▰▱▱" for N out of M.
    progress_bar() {
        local n="$1" m="$2" segs=12 filled i out=""
        [ "$m" -le 0 ] && m=1
        filled=$((n * segs / m))
        for ((i = 0; i < segs; i++)); do
            if [ "$i" -lt "$filled" ]; then out="$out$G_FULL"; else out="$out$G_EMPTY"; fi
        done
        printf '%s' "$out"
    }

    phase_open() {
        local title="$1" n m rest human pct
        printf "%s\n" "$(line_prefix)"
        case "$title" in
            [0-9]*/[0-9]*)
                n="${title%%/*}"
                rest="${title#*/}"
                m="${rest%% *}"
                human="${title#*- }"
                pct=$((n * 100 / m))
                printf "%s  %sStep %s/%s%s   %s%s%s %s%d%%%s\n" \
                    "$(node_prefix)" "$BOLD" "$n" "$m" "$RESET" \
                    "$ACCENT" "$(progress_bar "$n" "$m")" "$RESET" "$DIM" "$pct" "$RESET"
                printf "%s  %s%s%s\n" "$(line_prefix)" "$BOLD" "$human" "$RESET"
                ;;
            *)
                printf "%s  %s%s%s\n" "$(node_prefix)" "$BOLD" "$title" "$RESET"
                ;;
        esac
        printf "%s\n" "$(line_prefix)"
    }

    phase_close() {
        local title="$1"
        printf "%s\n" "$(line_prefix)"
        printf "%s  %s%s complete%s\n" "${GREEN}${OK_MARK}${RESET}" "$DIM" "$title" "$RESET"
    }

    # ui_banner TITLE SUBTITLE [TAGLINE]
    # Three-row boxed banner. TAGLINE defaults to "catppuccin frappe · <depth>".
    ui_banner() {
        local title="$1" subtitle="$2" tagline="${3:-}"
        local inner=$((UI_COLS - 2)) depth_label sep
        case "$UI_DEPTH" in
            true) depth_label="truecolor" ;;
            256) depth_label="256-color" ;;
            16) depth_label="16-color" ;;
            *) depth_label="plain" ;;
        esac
        [ "$UI_UNICODE" = 1 ] && sep="·" || sep="-"
        [ -z "$tagline" ] && tagline="catppuccin frappe $sep $depth_label"

        _brow() {
            local plain="$1" colored="$2" pad
            pad=$((inner - 1 - ${#plain}))
            [ "$pad" -lt 0 ] && pad=0
            printf '%s%s%s %s%s%s%s%s\n' \
                "$ACCENT" "$BOX_V" "$RESET" "$colored" "$(repeat ' ' "$pad")" "$ACCENT" "$BOX_V" "$RESET"
        }

        printf "\n"
        printf '%s%s%s%s%s\n' "$ACCENT" "$BOX_TL" "$(repeat "$BOX_H" "$inner")" "$BOX_TR" "$RESET"
        _brow "${NODE} ${title}" "${ACCENT}${BOLD}${NODE} ${title}${RESET}"
        _brow "$subtitle" "${BOLD}${subtitle}${RESET}"
        _brow "$tagline" "${DIM}${tagline}${RESET}"
        printf '%s%s%s%s%s\n' "$ACCENT" "$BOX_BL" "$(repeat "$BOX_H" "$inner")" "$BOX_BR" "$RESET"
    }

    # ─── TTY prompts ─────────────────────────────────────────────────────────
    # `prompt_*` always read/write via /dev/tty so they survive piped stdin
    # (`curl | bash`-style invocations) and redirected stdout. They degrade to
    # the supplied default when no tty is available or ASSUME_YES=1.

    have_tty() { (exec </dev/tty >/dev/tty) 2>/dev/null; }

    prompt_read() {
        local __out="$1" prompt="$2" response
        printf "%s  %s" "$(line_prefix)" "$prompt" >/dev/tty
        IFS= read -r response </dev/tty || response=""
        printf -v "$__out" '%s' "$response"
    }

    restore_terminal() {
        [ -n "${UI_STTY_SAVED:-}" ] && stty "$UI_STTY_SAVED" </dev/tty 2>/dev/null
        UI_STTY_SAVED=""
        [ "$UI_COLOR" = 1 ] && printf '\033[?25h' 2>/dev/null
    }

    # ui_select_raw OUTVAR DEFAULT "val|label"... — interactive ↑/↓ menu.
    # See install.sh for the TTY contract; same code, same invariants. The
    # ESC-rest read uses `-t 1` which honours fractional values in zsh but
    # not bash 3.2; that's fine here because chezup.sh runs under bash.
    ui_select_raw() {
        local __out="$1" default="$2"
        shift 2
        local opts=("$@") n=$# i sel=0 key rest val saved

        for ((i = 0; i < n; i++)); do
            [ "${opts[$i]%%|*}" = "$default" ] && sel=$i
        done

        _ui_draw() {
            local j v l
            for ((j = 0; j < n; j++)); do
                v="${opts[$j]%%|*}"
                l="${opts[$j]#*|}"
                if [ "$j" -eq "$sel" ]; then
                    printf '\r\033[2K%s    %s%s %s%s%s\n' "$(line_prefix)" "$ACCENT" "$G_POINTER" "$BOLD" "$l" "$RESET" >/dev/tty
                else
                    printf '\r\033[2K%s    %s%s %s%s\n' "$(line_prefix)" "$DIM" "$G_OFF" "$l" "$RESET" >/dev/tty
                fi
            done
        }

        saved="$(stty -g </dev/tty 2>/dev/null)"
        UI_STTY_SAVED="$saved"
        stty -echo -icanon min 1 time 0 </dev/tty 2>/dev/null
        [ "$UI_COLOR" = 1 ] && printf '\033[?25l' >/dev/tty

        _ui_draw
        while :; do
            IFS= read -rsn1 key </dev/tty || break
            case "$key" in
                $'\033')
                    read -rsn2 -t 1 rest </dev/tty
                    case "$rest" in
                        '[A') sel=$(((sel - 1 + n) % n)) ;;
                        '[B') sel=$(((sel + 1) % n)) ;;
                    esac
                    ;;
                k | K) sel=$(((sel - 1 + n) % n)) ;;
                j | J) sel=$(((sel + 1) % n)) ;;
                '' | $'\n' | $'\r') break ;;
                [1-9])
                    if [ "$key" -ge 1 ] && [ "$key" -le "$n" ]; then
                        sel=$((key - 1))
                        break
                    fi
                    ;;
            esac
            printf '\033[%dA' "$n" >/dev/tty
            _ui_draw
        done

        [ "$UI_COLOR" = 1 ] && printf '\033[?25h' >/dev/tty
        stty "$saved" </dev/tty 2>/dev/null
        UI_STTY_SAVED=""

        val="${opts[$sel]%%|*}"
        printf -v "$__out" '%s' "$val"
    }

    _choice_numbered() {
        local __out="$1" default="$2"
        shift 2
        local opts=("$@") n=$# i answer value label
        for ((i = 0; i < n; i++)); do
            value="${opts[$i]%%|*}"
            label="${opts[$i]#*|}"
            if [ "$value" = "$default" ]; then
                printf "%s    %s%d%s %s %s(current)%s\n" "$(line_prefix)" "$ACCENT" $((i + 1)) "$RESET" "$label" "$DIM" "$RESET" >/dev/tty
            else
                printf "%s    %s%d%s %s\n" "$(line_prefix)" "$ACCENT" $((i + 1)) "$RESET" "$label" >/dev/tty
            fi
        done
        while :; do
            prompt_read answer "${G_POINTER} choose 1-$n, or Enter for ${BOLD}$default${RESET}: "
            [ -z "$answer" ] && {
                printf -v "$__out" '%s' "$default"
                return
            }
            case "$answer" in
                '' | *[!0-9]*) warn "enter a number from 1 to $n" ;;
                *)
                    if [ "$answer" -ge 1 ] && [ "$answer" -le "$n" ]; then
                        printf -v "$__out" '%s' "${opts[$((answer - 1))]%%|*}"
                        return
                    fi
                    warn "enter a number from 1 to $n"
                    ;;
            esac
        done
    }

    prompt_confirm() {
        local __out="$1" title="$2" default_yes="${3:-1}" answer default_label result def cv
        [ "$default_yes" = "1" ] && default_label="Y/n" || default_label="y/N"

        if ! have_tty || [ "${ASSUME_YES:-0}" = "1" ]; then
            [ "$default_yes" = "1" ] && result=true || result=false
            printf -v "$__out" '%s' "$result"
            printf "%s  %s%s:%s %s%s%s %s(default)%s\n" \
                "${GREEN}${OK_MARK}${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$([ "$result" = true ] && echo yes || echo no)" "$RESET" "$DIM" "$RESET"
            return
        fi

        if [ "$UI_RAW" = "1" ]; then
            [ "$default_yes" = "1" ] && def=yes || def=no
            printf "%s  %s%s%s  %s%s↑/↓ Enter%s\n" "$(node_prefix)" "$BOLD" "$title" "$RESET" "$DIM" "${ARROW_MARK} " "$RESET" >/dev/tty
            ui_select_raw cv "$def" "yes|Yes" "no|No"
            [ "$cv" = "yes" ] && result=true || result=false
        else
            while :; do
                if [ "$default_yes" = "1" ]; then
                    prompt_read answer "${BOLD}${title}${RESET} [$default_label] Enter for yes, or type n: "
                else
                    prompt_read answer "${BOLD}${title}${RESET} [$default_label] Enter for no, or type y: "
                fi
                case "${answer:-default}" in
                    default)
                        [ "$default_yes" = "1" ] && result=true || result=false
                        break
                        ;;
                    y | Y | yes | YES)
                        result=true
                        break
                        ;;
                    n | N | no | NO)
                        result=false
                        break
                        ;;
                    *) warn "answer y or n" ;;
                esac
            done
        fi
        printf -v "$__out" '%s' "$result"
        printf "%s  %s%s:%s %s%s%s\n" \
            "${GREEN}${OK_MARK}${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$([ "$result" = true ] && echo yes || echo no)" "$RESET"
    }
}
