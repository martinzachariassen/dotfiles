#!/usr/bin/env bash
# install.sh — guided wizard that bootstraps a Mac (fresh or existing) into the
# dotfiles' configured state. Vite/Clack-style TUI: arrow keys, checkboxes,
# vertical-bar gutter, in-place re-render. Pure bash + ANSI escapes — zero deps.
#
# Two ways to invoke:
#
#   Fresh Mac (no repo yet):
#     curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
#
#   Existing clone (or re-running):
#     bash ~/Dev/Personal/dotfiles/install.sh
#
# The wizard runs in six phases:
#   A. Probe        — read-only system survey
#   B. Choices      — profile + identity + 1Password + feature toggles
#                     (arrow-key picker, multi-select checkboxes)
#   C. Confirm      — review everything, last chance to abort
#   D. Execute      — Xcode CLT → Homebrew → chezmoi → clone → init → apply
#   E. Self-test    — functional verification
#   F. Next steps   — what to do after the wizard finishes
#
# Environment variables:
#   DRY_RUN=1         — print state-changing commands but don't run them
#   DOTFILES_REPO=URL — override the upstream repo URL
#   DOTFILES_DIR=PATH — override the local source directory
#   SKIP_BACKUP=1     — don't snapshot pre-existing legacy dotfiles
#   YES=1             — assume defaults at every prompt (CI / unattended)
#   NO_TUI=1          — force the plain-text fallback path

set -uo pipefail

# ─── Config (env-overridable) ─────────────────────────────────────────────────
REPO="${DOTFILES_REPO:-https://github.com/martinzachariassen/dotfiles.git}"
SOURCE_DIR="${DOTFILES_DIR:-$HOME/Dev/Personal/dotfiles}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_BACKUP="${SKIP_BACKUP:-0}"
ASSUME_YES="${YES:-0}"
NO_TUI="${NO_TUI:-0}"

# Feature toggle keys — kept in sync with .chezmoi.toml.tmpl's [data.features].
FEATURE_KEYS=(cloud iac databases macApps)

# ─── Colors ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'
    GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RED=$'\033[31m'
    CYAN=$'\033[36m'; MAGENTA=$'\033[35m'; GREY=$'\033[90m'
    RESET=$'\033[0m'
else
    BOLD=""; DIM=""; GREEN=""; YELLOW=""; BLUE=""; RED=""; CYAN=""; MAGENTA=""; GREY=""; RESET=""
fi

# ─── Logging primitives (used inside Phase output) ────────────────────────────
# These use the Clack-style gutter "│  " so output flows under the bar.
say()   { printf "%s  %s\n" "${CYAN}│${RESET}" "$1"; }
ok()    { printf "%s  %s✓%s %s\n" "${CYAN}│${RESET}" "$GREEN"  "$RESET" "$1"; }
info()  { printf "%s  %s•%s %s\n" "${CYAN}│${RESET}" "$BLUE"   "$RESET" "$1"; }
warn()  { printf "%s  %s!%s %s\n" "${CYAN}│${RESET}" "$YELLOW" "$RESET" "$1"; }
fail()  { printf "%s  %s✗%s %s\n" "${CYAN}│${RESET}" "$RED"    "$RESET" "$1"; }
dim()   { printf "%s  %s%s%s\n"   "${CYAN}│${RESET}" "$DIM"    "$1" "$RESET"; }
hr()    { printf "%s\n" "${CYAN}│${RESET}"; }

phase_open() {
    local title="$1"
    printf "%s\n"   "${CYAN}│${RESET}"
    printf "%s  %s%s%s\n" "${CYAN}◆${RESET}" "$BOLD" "$title" "$RESET"
    printf "%s\n"   "${CYAN}│${RESET}"
}
phase_close() {
    local title="$1"
    printf "%s\n"   "${CYAN}│${RESET}"
    printf "%s  %s%s done%s\n" "${GREEN}◇${RESET}" "$DIM" "$title" "$RESET"
}

# `run` wraps state-changing commands so DRY_RUN=1 just prints them.
run() {
    if [ "$DRY_RUN" = "1" ]; then
        printf "%s    %sDRY-RUN \$%s %s\n" "${CYAN}│${RESET}" "$DIM" "$RESET" "$*"
    else
        "$@"
    fi
}

# ─── TTY detection ────────────────────────────────────────────────────────────
# `test -r /dev/tty` lies in some sandboxes (says readable but open() fails),
# so we actually try to open it in a subshell and rely on the exit code.
have_tty() {
    ( exec </dev/tty >/dev/tty ) 2>/dev/null
}

# Whether we should run the full TUI (raw mode, arrow keys, cursor control).
# Falls back to plain prompts if NO_TUI=1, YES=1, missing stty, or no TTY.
tui_supported() {
    [ "$NO_TUI" = "1" ] && return 1
    [ "$ASSUME_YES" = "1" ] && return 1
    have_tty || return 1
    command -v stty >/dev/null 2>&1 || return 1
    return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# TUI primitives — raw-mode arrow-key prompts
# ═════════════════════════════════════════════════════════════════════════════
TUI_STTY_SAVE=""
TUI_ACTIVE=0   # 1 while raw mode is engaged

_tui_acquire() {
    [ "$TUI_ACTIVE" = "1" ] && return 0
    TUI_STTY_SAVE="$(stty -g </dev/tty 2>/dev/null)" || return 1
    stty -icanon -echo min 1 </dev/tty 2>/dev/null || return 1
    printf '\033[?25l' > /dev/tty 2>/dev/null    # hide cursor
    TUI_ACTIVE=1
    return 0
}
_tui_release() {
    [ "$TUI_ACTIVE" = "1" ] || return 0
    printf '\033[?25h' > /dev/tty 2>/dev/null    # show cursor
    [ -n "$TUI_STTY_SAVE" ] && stty "$TUI_STTY_SAVE" </dev/tty 2>/dev/null
    TUI_ACTIVE=0
}

# Always restore on exit, even on Ctrl-C / unexpected death.
trap '_tui_release' EXIT
trap '_tui_release; printf "\n%s  %s✗%s aborted\n" "${CYAN}│${RESET}" "$RED" "$RESET"; exit 130' INT TERM

# Read one normalised keystroke. Echoes one of:
#   up · down · left · right · enter · space · esc · abort · char:X
_tui_key() {
    local k rest
    IFS= read -rsn1 k </dev/tty 2>/dev/null || { echo abort; return; }
    case "$k" in
        $'\033')
            # Escape sequence — try to read up to 2 more bytes within 50ms.
            # On a bare ESC, the timeout fires and rest stays empty.
            IFS= read -rsn2 -t 0.05 rest </dev/tty 2>/dev/null || rest=""
            case "$rest" in
                '[A') echo up    ;;
                '[B') echo down  ;;
                '[C') echo right ;;
                '[D') echo left  ;;
                *)    echo esc   ;;
            esac
            ;;
        ' ')        echo space ;;
        '')         echo enter ;;
        $'\003')    echo abort ;;
        *)          echo "char:$k" ;;
    esac
}

# Render a "prompt block" — a series of lines, returning the count so we can
# rewind for the next render.
_tui_emit() {
    local count=0 line
    for line in "$@"; do
        printf '%s\n' "$line" > /dev/tty
        count=$((count + 1))
    done
    return "$count"   # exit code carries the count (0–255)
}
# Move cursor up N lines and clear from cursor to end of screen.
_tui_rewind() {
    local n="$1"
    [ "$n" -le 0 ] && return
    printf '\033[%dA\033[J' "$n" > /dev/tty
}

# ── tui_select_one __outvar TITLE LABEL1 LABEL2 [...]
# Single-select radio menu. Arrow keys to navigate, Enter to confirm.
tui_select_one() {
    local __out="$1" title="$2"
    shift 2
    local opts=("$@") n=$# cursor=0

    if ! tui_supported || ! _tui_acquire; then
        # Fallback: first option wins.
        printf -v "$__out" '%s' "${opts[0]}"
        printf '%s  %s%s%s %s%s%s  %s(default)%s\n' \
            "${GREEN}◇${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "${opts[0]}" "$RESET" "$DIM" "$RESET"
        return
    fi

    local lines i lc
    while :; do
        # Build the prompt block
        lines=()
        lines+=("${CYAN}◆${RESET}  ${BOLD}${title}${RESET}")
        for ((i=0; i<n; i++)); do
            if [ "$i" -eq "$cursor" ]; then
                lines+=("${CYAN}│${RESET}  ${CYAN}●${RESET} ${CYAN}${opts[$i]}${RESET}")
            else
                lines+=("${CYAN}│${RESET}  ${DIM}○${RESET} ${DIM}${opts[$i]}${RESET}")
            fi
        done
        lines+=("${CYAN}│${RESET}  ${GREY}↑↓ navigate · ↵ select${RESET}")
        _tui_emit "${lines[@]}"
        lc=$?

        case "$(_tui_key)" in
            up)               cursor=$(( (cursor - 1 + n) % n )); _tui_rewind "$lc" ;;
            down)             cursor=$(( (cursor + 1) % n ));     _tui_rewind "$lc" ;;
            char:k|char:K)    cursor=$(( (cursor - 1 + n) % n )); _tui_rewind "$lc" ;;
            char:j|char:J)    cursor=$(( (cursor + 1) % n ));     _tui_rewind "$lc" ;;
            enter)            break ;;
            abort|esc)        _tui_release; printf "\n%s  %s✗%s aborted\n" "${CYAN}│${RESET}" "$RED" "$RESET"; exit 130 ;;
            *)                _tui_rewind "$lc" ;;
        esac
    done

    # Collapse: rewind the whole block, print the summary line.
    _tui_rewind "$lc"
    printf '%s  %s%s%s %s%s%s\n' \
        "${GREEN}◇${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "${opts[$cursor]}" "$RESET" > /dev/tty
    _tui_release
    printf -v "$__out" '%s' "${opts[$cursor]}"
}

# ── tui_confirm __outvar TITLE [DEFAULT_YES=1]
# Arrow-key Yes/No. Default to Yes unless DEFAULT_YES=0. Stores "true"/"false".
tui_confirm() {
    local __out="$1" title="$2" def_yes="${3:-1}"
    local cursor
    if [ "$def_yes" = "1" ]; then cursor=0; else cursor=1; fi

    if ! tui_supported || ! _tui_acquire; then
        if [ "$def_yes" = "1" ]; then
            printf -v "$__out" 'true'
            printf '%s  %s%s%s %sYes%s  %s(default)%s\n' \
                "${GREEN}◇${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$RESET" "$DIM" "$RESET"
        else
            printf -v "$__out" 'false'
            printf '%s  %s%s%s %sNo%s  %s(default)%s\n' \
                "${GREEN}◇${RESET}" "$BOLD" "$title" "$RESET" "$YELLOW" "$RESET" "$DIM" "$RESET"
        fi
        return
    fi

    local lines lc opts=("Yes" "No")
    while :; do
        lines=()
        lines+=("${CYAN}◆${RESET}  ${BOLD}${title}${RESET}")
        local row="${CYAN}│${RESET}  "
        if [ "$cursor" -eq 0 ]; then
            row+="${CYAN}●${RESET} ${CYAN}Yes${RESET}    ${DIM}○ No${RESET}"
        else
            row+="${DIM}○ Yes${RESET}    ${CYAN}●${RESET} ${CYAN}No${RESET}"
        fi
        lines+=("$row")
        lines+=("${CYAN}│${RESET}  ${GREY}← → toggle · ↵ confirm${RESET}")
        _tui_emit "${lines[@]}"
        lc=$?
        case "$(_tui_key)" in
            left|up|char:h)         cursor=0 ;;
            right|down|char:l)      cursor=1 ;;
            char:y|char:Y)          cursor=0; _tui_rewind "$lc"; break ;;
            char:n|char:N)          cursor=1; _tui_rewind "$lc"; break ;;
            enter)                  break ;;
            abort|esc)              _tui_release; printf "\n%s  %s✗%s aborted\n" "${CYAN}│${RESET}" "$RED" "$RESET"; exit 130 ;;
        esac
        _tui_rewind "$lc"
    done
    _tui_rewind "$lc"
    if [ "$cursor" -eq 0 ]; then
        printf '%s  %s%s%s %sYes%s\n' "${GREEN}◇${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$RESET" > /dev/tty
        printf -v "$__out" 'true'
    else
        printf '%s  %s%s%s %sNo%s\n'  "${GREEN}◇${RESET}" "$BOLD" "$title" "$RESET" "$YELLOW" "$RESET" > /dev/tty
        printf -v "$__out" 'false'
    fi
    _tui_release
}

# ── tui_select_many __outvar TITLE LABEL1 LABEL2 [...]
# Multi-select with checkboxes. Space toggles, Enter confirms. All start checked.
# Stores result as space-separated "1"/"0" matching input order.
#   tui_select_many BITS "Features" "Cloud" "IaC" "Databases" "Mac apps"
#   read -ra arr <<< "$BITS"   # arr[0]==1 means Cloud is checked
tui_select_many() {
    local __out="$1" title="$2"
    shift 2
    local opts=("$@") n=$# cursor=0
    local checked=() i
    for ((i=0; i<n; i++)); do checked[i]=1; done

    if ! tui_supported || ! _tui_acquire; then
        # Fallback: all stay checked.
        printf -v "$__out" '%s' "${checked[*]}"
        printf '%s  %s%s%s  %s(all defaults)%s\n' \
            "${GREEN}◇${RESET}" "$BOLD" "$title" "$RESET" "$DIM" "$RESET"
        for ((i=0; i<n; i++)); do
            printf '%s    %s◼%s %s\n' "${CYAN}│${RESET}" "$GREEN" "$RESET" "${opts[$i]}"
        done
        return
    fi

    local lines lc row
    while :; do
        lines=()
        lines+=("${CYAN}◆${RESET}  ${BOLD}${title}${RESET}")
        for ((i=0; i<n; i++)); do
            local mark
            if [ "${checked[$i]}" = "1" ]; then
                mark="${GREEN}◼${RESET}"
            else
                mark="${DIM}◻${RESET}"
            fi
            if [ "$i" -eq "$cursor" ]; then
                row="${CYAN}│${RESET}  ${mark} ${CYAN}${opts[$i]}${RESET}"
            else
                if [ "${checked[$i]}" = "1" ]; then
                    row="${CYAN}│${RESET}  ${mark} ${opts[$i]}"
                else
                    row="${CYAN}│${RESET}  ${mark} ${DIM}${opts[$i]}${RESET}"
                fi
            fi
            lines+=("$row")
        done
        lines+=("${CYAN}│${RESET}  ${GREY}↑↓ navigate · space toggle · ↵ confirm${RESET}")
        _tui_emit "${lines[@]}"
        lc=$?

        case "$(_tui_key)" in
            up|char:k|char:K)
                cursor=$(( (cursor - 1 + n) % n )) ;;
            down|char:j|char:J)
                cursor=$(( (cursor + 1) % n )) ;;
            space)
                if [ "${checked[$cursor]}" = "1" ]; then checked[cursor]=0; else checked[cursor]=1; fi
                ;;
            char:a|char:A)
                # 'a' selects all
                for ((i=0; i<n; i++)); do checked[i]=1; done ;;
            char:i|char:I)
                # 'i' inverts selection
                for ((i=0; i<n; i++)); do
                    if [ "${checked[$i]}" = "1" ]; then checked[i]=0; else checked[i]=1; fi
                done ;;
            enter)
                _tui_rewind "$lc"
                break ;;
            abort|esc)
                _tui_release
                printf "\n%s  %s✗%s aborted\n" "${CYAN}│${RESET}" "$RED" "$RESET"
                exit 130 ;;
        esac
        _tui_rewind "$lc"
    done

    # Collapse: print summary header + a clean list of just the checked items.
    printf '%s  %s%s%s\n' "${GREEN}◇${RESET}" "$BOLD" "$title" "$RESET" > /dev/tty
    for ((i=0; i<n; i++)); do
        if [ "${checked[$i]}" = "1" ]; then
            printf '%s    %s◼%s %s\n' "${CYAN}│${RESET}" "$GREEN" "$RESET" "${opts[$i]}" > /dev/tty
        else
            printf '%s    %s◻ %s%s\n' "${CYAN}│${RESET}" "$DIM" "${opts[$i]}" "$RESET" > /dev/tty
        fi
    done
    _tui_release
    printf -v "$__out" '%s' "${checked[*]}"
}

# ── tui_text __outvar TITLE [DEFAULT] [HINT]
# Single-line text input. Uses readline (no raw mode) since editing matters.
tui_text() {
    local __out="$1" title="$2" default="${3:-}" hint="${4:-}"
    local answer=""

    if ! have_tty || [ "$ASSUME_YES" = "1" ] || [ "$NO_TUI" = "1" ]; then
        printf -v "$__out" '%s' "$default"
        if [ -n "$default" ]; then
            printf '%s  %s%s%s %s%s%s  %s(default)%s\n' \
                "${GREEN}◇${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$default" "$RESET" "$DIM" "$RESET"
        else
            printf '%s  %s%s%s  %s(skipped)%s\n' \
                "${GREEN}◇${RESET}" "$BOLD" "$title" "$RESET" "$DIM" "$RESET"
        fi
        return
    fi

    # Header
    printf '%s  %s%s%s\n' "${CYAN}◆${RESET}" "$BOLD" "$title" "$RESET" > /dev/tty
    [ -n "$hint" ] && printf '%s  %s%s%s\n' "${CYAN}│${RESET}" "$GREY" "$hint" "$RESET" > /dev/tty
    local prompt_prefix
    if [ -n "$default" ]; then
        prompt_prefix="${CYAN}│${RESET}  ${DIM}[${default}]${RESET} ❯ "
    else
        prompt_prefix="${CYAN}│${RESET}  ❯ "
    fi
    printf '%s' "$prompt_prefix" > /dev/tty
    IFS= read -r answer < /dev/tty || answer=""
    [ -z "$answer" ] && answer="$default"

    # Collapse: rewind 2 or 3 lines (header + optional hint + input).
    local rewind_n=2
    [ -n "$hint" ] && rewind_n=3
    _tui_rewind "$rewind_n"
    if [ -n "$answer" ]; then
        printf '%s  %s%s%s %s%s%s\n' \
            "${GREEN}◇${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$answer" "$RESET" > /dev/tty
    else
        printf '%s  %s%s%s  %s(blank)%s\n' \
            "${GREEN}◇${RESET}" "$BOLD" "$title" "$RESET" "$DIM" "$RESET" > /dev/tty
    fi
    printf -v "$__out" '%s' "$answer"
}

# ═════════════════════════════════════════════════════════════════════════════
# Banner — Clack-style ┌ opener
# ═════════════════════════════════════════════════════════════════════════════
banner() {
    local subtitle="${BOLD}dotfiles wizard${RESET}"
    printf "\n"
    printf "%s\n"     "${CYAN}┌${RESET}  ${subtitle}"
    printf "%s  %s\n" "${CYAN}│${RESET}" "${DIM}Personal macOS setup managed by chezmoi — backend-dev preset.${RESET}"
    if [ "$DRY_RUN" = "1" ]; then
        printf "%s  %s\n" "${CYAN}│${RESET}" "${YELLOW}${BOLD}DRY-RUN MODE — no changes will be made.${RESET}"
    fi
    if [ "$ASSUME_YES" = "1" ]; then
        printf "%s  %s\n" "${CYAN}│${RESET}" "${YELLOW}${BOLD}YES MODE — accepting recommended defaults.${RESET}"
    fi
    printf "%s\n" "${CYAN}│${RESET}"
    printf "%s  %s\n" "${CYAN}│${RESET}" "Six phases: probe → choices → confirm → execute → self-test → next steps."
    printf "%s  %s\n" "${CYAN}│${RESET}" "${DIM}~15 min, almost all of it Homebrew downloading.${RESET}"
    if tui_supported; then
        printf "%s  %s\n" "${CYAN}│${RESET}" "${DIM}Use ↑↓ to navigate, space to toggle, ↵ to confirm, ctrl-c to abort.${RESET}"
    fi
    if have_tty && [ "$ASSUME_YES" != "1" ]; then
        printf "%s\n" "${CYAN}│${RESET}"
        printf "%s  %sPress ↵ to begin%s " "${CYAN}│${RESET}" "$BOLD" "$RESET" > /dev/tty
        IFS= read -r _ < /dev/tty || true
        _tui_rewind 2
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE A — Probe: read-only system survey
# ═════════════════════════════════════════════════════════════════════════════
probe() {
    phase_open "Phase A · Discovery"

    if [ "$(uname -s)" != "Darwin" ]; then
        fail "this wizard only supports macOS (you're on $(uname -s))"
        exit 1
    fi
    PROBE_ARCH="$(uname -m)"
    PROBE_OS_VER="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
    if [ "$PROBE_ARCH" = "arm64" ]; then
        ok "macOS $PROBE_OS_VER on Apple Silicon"
    else
        warn "macOS $PROBE_OS_VER on Intel — this repo targets Apple Silicon. Brew will land at /usr/local."
    fi

    if xcode-select -p >/dev/null 2>&1; then
        ok "Xcode Command Line Tools present"
    else
        info "Xcode CLT missing — wizard will install"
    fi

    if command -v brew >/dev/null 2>&1; then
        ok "Homebrew at $(command -v brew)"
    else
        info "Homebrew not installed — wizard will install"
    fi

    if command -v chezmoi >/dev/null 2>&1; then
        ok "$(chezmoi --version 2>/dev/null | head -1)"
    else
        info "chezmoi not installed — wizard will install"
    fi

    PROBE_CHEZMOI_CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
    if [ -f "$PROBE_CHEZMOI_CONFIG" ]; then
        ok "prior chezmoi config found — you can re-use those answers"
        PROBE_HAS_CHEZMOI_CONFIG=1
    else
        info "no prior chezmoi config — first-time setup"
        PROBE_HAS_CHEZMOI_CONFIG=0
    fi

    if [ -d "$SOURCE_DIR/.git" ]; then
        ok "repo already cloned at $SOURCE_DIR"
        PROBE_REPO_CLONED=1
    else
        info "repo not yet cloned (will clone to $SOURCE_DIR)"
        PROBE_REPO_CLONED=0
    fi

    if [ -d /Applications/1Password.app ]; then
        ok "1Password.app installed"
        PROBE_OP_APP=1
    else
        info "1Password.app not yet installed (Brewfile pulls it)"
        PROBE_OP_APP=0
    fi

    PROBE_LEGACY_FILES=()
    for f in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.gitconfig" "$HOME/.bash_profile" "$HOME/.bashrc"; do
        if [ -f "$f" ] && [ ! -L "$f" ] && [ -s "$f" ]; then
            PROBE_LEGACY_FILES+=("$f")
        fi
    done
    if [ ${#PROBE_LEGACY_FILES[@]} -gt 0 ]; then
        warn "found ${#PROBE_LEGACY_FILES[@]} legacy shell/git file(s) that will shadow this repo's XDG layout"
        for f in "${PROBE_LEGACY_FILES[@]}"; do dim "    $f"; done
    else
        ok "no legacy ~/.zshrc / ~/.gitconfig / ~/.bash* — clean slate"
    fi

    if [ -d "$HOME/.oh-my-zsh" ]; then
        warn "oh-my-zsh at ~/.oh-my-zsh — will conflict with this repo's plain-zsh layout"
        PROBE_OMZ=1
    else
        PROBE_OMZ=0
    fi

    phase_close "Phase A"
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE B — Choices
# ═════════════════════════════════════════════════════════════════════════════
choices() {
    phase_open "Phase B · Choices"

    # ─── Re-use prior answers? ───────────────────────────────────────────────
    REUSE_PRIOR=false
    if [ "$PROBE_HAS_CHEZMOI_CONFIG" = "1" ]; then
        tui_confirm REUSE_PRIOR "Re-use answers from your existing chezmoi config?" 1
        if [ "$REUSE_PRIOR" = "true" ]; then
            local data_json
            data_json="$(chezmoi data --format=json 2>/dev/null || echo '{}')"
            CHOICE_NAME="$(printf '%s' "$data_json" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')"
            CHOICE_EMAIL="$(printf '%s' "$data_json" | sed -n 's/.*"email":"\([^"]*\)".*/\1/p')"
            CHOICE_SIGNINGKEY="$(printf '%s' "$data_json" | sed -n 's/.*"signingKey":"\([^"]*\)".*/\1/p')"
            CHOICE_PROFILE="$(printf '%s' "$data_json" | sed -n 's/.*"profile":"\([^"]*\)".*/\1/p')"
            CHOICE_PROFILE="${CHOICE_PROFILE:-personal}"
            CHOICE_USE_OP="$(printf '%s' "$data_json" | grep -o '"useOnePassword":[a-z]*' | cut -d: -f2)"
            CHOICE_USE_OP="${CHOICE_USE_OP:-true}"
            local key val
            for key in "${FEATURE_KEYS[@]}"; do
                val="$(printf '%s' "$data_json" | grep -o "\"$key\":[a-z]*" | head -1 | cut -d: -f2)"
                eval "CHOICE_FEAT_${key}=\"\${val:-true}\""
            done
            ok "re-using prior answers (skipping prompts)"
            choices_existing_files
            phase_close "Phase B"
            return
        fi
    fi

    # ─── Profile ─────────────────────────────────────────────────────────────
    tui_select_one CHOICE_PROFILE "Which profile?" \
        "personal — adds Brewfile.personal (Claude apps, etc.)" \
        "work     — adds Brewfile.work (the casks you fill in)" \
        "both     — adds both"
    # Strip the description suffix
    CHOICE_PROFILE="${CHOICE_PROFILE%% *}"

    # ─── Identity ────────────────────────────────────────────────────────────
    local default_name default_email
    default_name="$(git config --global user.name 2>/dev/null || echo '')"
    default_email="$(git config --global user.email 2>/dev/null || echo '')"
    tui_text CHOICE_NAME  "Full name"  "$default_name"  "Goes in ~/.config/git/config user.name"
    tui_text CHOICE_EMAIL "Git email"  "$default_email" "noreply addresses work fine"

    # ─── 1Password ───────────────────────────────────────────────────────────
    tui_confirm CHOICE_USE_OP "Use 1Password for SSH auth + git signing?" 1
    if [ "$CHOICE_USE_OP" = "true" ]; then
        tui_text CHOICE_SIGNINGKEY "SSH signing public key" "" \
            "Paste your full ssh-ed25519 line from the 1Password item (or leave blank to set later)"
    else
        CHOICE_SIGNINGKEY=""
    fi

    # ─── Features (single multi-select) ──────────────────────────────────────
    local feat_bits
    tui_select_many feat_bits "Optional features (space to toggle, ↵ to confirm)" \
        "Cloud — Kubernetes (kubectl/k9s/kubectx/stern/helm) + Azure CLI + gcloud" \
        "IaC   — Terraform + tflint + terraform-docs" \
        "DBs   — pgcli + mysql-client + redis-cli" \
        "Apps  — Rectangle + Raycast + Stats + Chrome + dive"
    local i=0 key
    # shellcheck disable=SC2206
    local feat_arr=($feat_bits)
    for key in "${FEATURE_KEYS[@]}"; do
        if [ "${feat_arr[$i]:-1}" = "1" ]; then
            eval "CHOICE_FEAT_${key}=true"
        else
            eval "CHOICE_FEAT_${key}=false"
        fi
        i=$((i + 1))
    done

    # ─── Existing-file handling ──────────────────────────────────────────────
    choices_existing_files
    phase_close "Phase B"
}

choices_existing_files() {
    CHOICE_BACKUP_LEGACY=true
    CHOICE_REMOVE_OMZ=false
    if [ ${#PROBE_LEGACY_FILES[@]} -gt 0 ]; then
        tui_confirm CHOICE_BACKUP_LEGACY \
            "Back up ${#PROBE_LEGACY_FILES[@]} legacy file(s) + remove the originals?" 1
    fi
    if [ "$PROBE_OMZ" = "1" ]; then
        tui_confirm CHOICE_REMOVE_OMZ "Uninstall oh-my-zsh before installing dotfiles?" 1
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE C — Confirm
# ═════════════════════════════════════════════════════════════════════════════
confirm_phase() {
    phase_open "Phase C · Confirm"

    local feat_summary=()
    local key var val
    for key in "${FEATURE_KEYS[@]}"; do
        var="CHOICE_FEAT_${key}"
        val="${!var}"
        if [ "$val" = "true" ]; then
            feat_summary+=("${GREEN}+${RESET}${key}")
        else
            feat_summary+=("${DIM}-${key}${RESET}")
        fi
    done
    local key_short=""
    if [ -n "$CHOICE_SIGNINGKEY" ]; then
        key_short="${CHOICE_SIGNINGKEY:0:40}…"
    else
        key_short="${DIM}(none — set later)${RESET}"
    fi

    say "${BOLD}Profile:${RESET}      $CHOICE_PROFILE"
    say "${BOLD}Name:${RESET}         ${CHOICE_NAME:-${DIM}(blank)${RESET}}"
    say "${BOLD}Email:${RESET}        ${CHOICE_EMAIL:-${DIM}(blank)${RESET}}"
    say "${BOLD}1Password:${RESET}    $([ "$CHOICE_USE_OP" = "true" ] && echo "${GREEN}yes${RESET}" || echo "${YELLOW}no${RESET}")"
    say "${BOLD}Signing key:${RESET}  $key_short"
    say "${BOLD}Features:${RESET}     ${feat_summary[*]}"
    say "${BOLD}Repo:${RESET}         $REPO"
    say "${BOLD}Source dir:${RESET}   $SOURCE_DIR"
    say "${BOLD}Legacy backup:${RESET} $([ "${CHOICE_BACKUP_LEGACY:-true}" = "true" ] && echo yes || echo no)"
    say "${BOLD}Remove OMZ:${RESET}   $([ "${CHOICE_REMOVE_OMZ:-false}" = "true" ] && echo yes || echo no)"

    hr
    local proceed
    tui_confirm proceed "Proceed with installation?" 1
    if [ "$proceed" != "true" ]; then
        info "aborted — nothing has changed"
        phase_close "Phase C"
        exit 0
    fi
    phase_close "Phase C"
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE D — Execute
# ═════════════════════════════════════════════════════════════════════════════
execute() {
    phase_open "Phase D · Execute"

    if [ "$SKIP_BACKUP" != "1" ] && [ "${CHOICE_BACKUP_LEGACY:-true}" = "true" ] && [ ${#PROBE_LEGACY_FILES[@]} -gt 0 ]; then
        BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
        info "backing up ${#PROBE_LEGACY_FILES[@]} legacy file(s) to $BACKUP_DIR"
        local rel
        for f in "${PROBE_LEGACY_FILES[@]}"; do
            rel="${f#"$HOME"/}"
            run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
            run cp -p "$f" "$BACKUP_DIR/$rel"
            run rm -f "$f"
        done
        ok "legacy files backed up + removed"
    fi
    if [ "${CHOICE_REMOVE_OMZ:-false}" = "true" ] && [ -d "$HOME/.oh-my-zsh" ]; then
        info "uninstalling oh-my-zsh (non-interactive)"
        run bash -c 'yes | "$HOME/.oh-my-zsh/tools/uninstall.sh"' || warn "oh-my-zsh uninstaller errored — continuing"
    fi

    info "Xcode Command Line Tools"
    if ! xcode-select -p >/dev/null 2>&1; then
        info "triggering install (a GUI dialog will appear)"
        run xcode-select --install || true
        if [ "$DRY_RUN" != "1" ]; then
            printf "%s    %swaiting for install to complete" "${CYAN}│${RESET}" "$DIM"
            local _i
            for _i in $(seq 1 240); do
                if xcode-select -p >/dev/null 2>&1; then printf "%s\n" "$RESET"; break; fi
                printf "."
                sleep 5
            done
            if ! xcode-select -p >/dev/null 2>&1; then
                printf "%s\n" "$RESET"
                fail "Xcode CLT install timed out (20 min) — re-run the wizard"
                exit 1
            fi
        fi
    fi
    ok "Xcode CLT at $(xcode-select -p 2>/dev/null || echo '<dry-run>')"

    info "Homebrew"
    if ! command -v brew >/dev/null 2>&1; then
        info "installing Homebrew (non-interactive)"
        run /bin/bash -c \
            "NONINTERACTIVE=1 \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    fi
    if [ "$DRY_RUN" != "1" ] && [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    ok "Homebrew at $(command -v brew 2>/dev/null || echo '<dry-run>')"

    info "chezmoi"
    if ! command -v chezmoi >/dev/null 2>&1; then
        run brew install chezmoi
    fi
    ok "chezmoi at $(command -v chezmoi 2>/dev/null || echo '<dry-run>')"

    info "Repository at $SOURCE_DIR"
    if [ ! -d "$SOURCE_DIR/.git" ]; then
        run mkdir -p "$(dirname "$SOURCE_DIR")"
        run git clone "$REPO" "$SOURCE_DIR"
    else
        ok "already cloned"
    fi

    info "Configuring chezmoi with your answers from Phase B (no further prompts)"
    run mkdir -p "$HOME/.config/chezmoi"
    local init_flags=(
        "--source=$SOURCE_DIR"
        "--promptString=name=$CHOICE_NAME"
        "--promptString=email=$CHOICE_EMAIL"
        "--promptString=signingKey=$CHOICE_SIGNINGKEY"
        "--promptChoice=profile=$CHOICE_PROFILE"
        "--promptBool=useOnePassword=$CHOICE_USE_OP"
    )
    local var
    for key in "${FEATURE_KEYS[@]}"; do
        var="CHOICE_FEAT_${key}"
        init_flags+=("--promptBool=features.${key}=${!var}")
    done
    run chezmoi init "${init_flags[@]}"
    ok "chezmoi configured"

    info "Applying dotfiles (brew bundle dominates — ~10–15 min)"
    run chezmoi apply
    ok "chezmoi apply complete"
    phase_close "Phase D"
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE E — Self-test
# ═════════════════════════════════════════════════════════════════════════════
self_test() {
    phase_open "Phase E · Self-test"
    if [ "$DRY_RUN" = "1" ]; then
        ok "DRY-RUN: skipping"
        phase_close "Phase E"
        return
    fi
    chmod -R go-w /opt/homebrew/share/zsh* 2>/dev/null || true

    _v() {
        local name="$1"; shift
        if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
    }
    _vf() {
        local name="$1" cmd="$2" out
        if out=$(eval "$cmd" 2>&1); then ok "$name"; else fail "$name — $out"; fi
    }

    say "${DIM}core${RESET}"
    _v "git"      git --version
    _v "chezmoi"  chezmoi --version
    _v "devbox"   devbox version
    # Nix isn't on PATH in this script's shell (Determinate adds it to /etc/zshrc
    # which only takes effect in new shells), so check the store directory and
    # the daemon LaunchDaemon instead — both are stable signals that Nix is
    # actually functional, not just half-installed.
    _vf "Nix store /nix"   "[ -d /nix ]"
    _vf "nix-daemon running" "launchctl list 2>/dev/null | grep -q org.nixos.nix-daemon"
    _v "starship" starship --version
    _v "zellij"   zellij --version
    _v "lazygit"  lazygit --version
    _v "direnv"   direnv version
    _v "delta"    delta --version
    _v "fzf"      fzf --version

    if [ "${CHOICE_FEAT_cloud:-true}" = "true" ]; then
        say "${DIM}cloud (enabled)${RESET}"
        _v "kubectl"  kubectl version --client=true
        _v "k9s"      k9s version
        _v "gh"       gh --version
        _v "az"       az --version
        _v "gcloud"   gcloud --version
    fi
    if [ "${CHOICE_FEAT_iac:-true}" = "true" ]; then
        say "${DIM}IaC (enabled)${RESET}"
        _v "terraform" terraform version
        _v "tflint"    tflint --version
    fi
    if [ "${CHOICE_FEAT_databases:-true}" = "true" ]; then
        say "${DIM}DBs (enabled)${RESET}"
        _v "pgcli"     pgcli --version
        _v "redis-cli" redis-cli --version
    fi

    say "${DIM}functional${RESET}"
    _vf "chezmoi doctor passes"  "chezmoi doctor 2>&1 | grep -qv '^error' || true"
    _vf "no legacy ~/.zshrc"     "[ ! -f \"\$HOME/.zshrc\" ]"
    _vf "no legacy ~/.gitconfig" "[ ! -f \"\$HOME/.gitconfig\" ]"
    _vf "no legacy ~/.zprofile"  "[ ! -f \"\$HOME/.zprofile\" ]"
    _vf "ZDOTDIR zshrc exists"   "[ -f \"\$HOME/.config/zsh/.zshrc\" ]"

    [ "$CHOICE_USE_OP" = "true" ] && _vf "op-ssh-sign present" "[ -x /Applications/1Password.app/Contents/MacOS/op-ssh-sign ]"
    _vf "JetBrainsMono Nerd Font" "ls \"\$HOME/Library/Fonts\" /Library/Fonts 2>/dev/null | grep -qi 'JetBrainsMono.*Nerd' || \
                                   ls /opt/homebrew/Caskroom/font-jetbrains-mono-nerd-font 2>/dev/null | grep -q ."

    say "${DIM}apps${RESET}"
    _v "Ghostty.app" test -d /Applications/Ghostty.app
    _v "VS Code.app" test -d "/Applications/Visual Studio Code.app"
    [ "$CHOICE_USE_OP" = "true" ] && _v "1Password.app" test -d /Applications/1Password.app

    say "${DIM}auth state (FYI — fix in Phase F)${RESET}"
    if command -v gh     >/dev/null && gh auth status >/dev/null 2>&1;             then ok "gh authenticated";     else warn "gh not authenticated";     fi
    if command -v az     >/dev/null && az account show >/dev/null 2>&1;            then ok "az authenticated";     else warn "az not authenticated";     fi
    if command -v gcloud >/dev/null && gcloud auth list 2>/dev/null | grep -q '\*'; then ok "gcloud authenticated"; else warn "gcloud not authenticated"; fi

    phase_close "Phase E"
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE F — Next steps + closing └
# ═════════════════════════════════════════════════════════════════════════════
next_steps() {
    phase_open "Phase F · Next steps"
    local n=1
    if [ "$CHOICE_USE_OP" = "true" ]; then
        say "$n. ${BOLD}Sign in to 1Password${RESET} ${DIM}(Settings → Developer → SSH agent)${RESET}"
        n=$((n+1))
    fi
    say "$n. ${BOLD}bash $SOURCE_DIR/bootstrap-auth.sh${RESET} ${DIM}— gh/az/gcloud sign-in + signing test${RESET}"
    n=$((n+1))
    say "$n. ${BOLD}exec zsh${RESET} ${DIM}— reload shell${RESET}"
    n=$((n+1))
    say "$n. ${BOLD}Restart your Mac${RESET} ${DIM}— some macOS defaults need a reboot${RESET}"
    hr
    say "${DIM}Diagnose anytime:${RESET} ${BOLD}bash $SOURCE_DIR/doctor.sh${RESET}"
    say "${DIM}Re-run wizard:${RESET}    ${BOLD}bash $SOURCE_DIR/install.sh${RESET}"
    printf "%s\n"   "${CYAN}│${RESET}"
    printf "%s  %sWizard complete.%s\n" "${GREEN}└${RESET}" "$BOLD" "$RESET"
    printf "\n"
}

# ═════════════════════════════════════════════════════════════════════════════
# Entry point
# ═════════════════════════════════════════════════════════════════════════════
main() {
    banner
    probe
    choices
    confirm_phase
    execute
    self_test
    next_steps
}

main "$@"
