#!/usr/bin/env bash
# install.sh - guided installer for this dotfiles repo.
#
# The wizard intentionally sticks to numbered menus and normal line input. That
# is less flashy than raw-mode arrow-key prompts, but it survives plain Terminal,
# Ghostty, SSH sessions, and pasted `curl | bash` installs.
#
# Usage:
#   bash install.sh
#   bash install.sh --configure-only
#   bash install.sh --reset-brew
#   bash install.sh --mirror-brew
#
# Environment:
#   DRY_RUN=1         print state-changing commands without running them
#   YES=1             accept recommended defaults (does not reset Homebrew)
#   SKIP_BACKUP=1     do not snapshot pre-existing legacy dotfiles
#   DOTFILES_REPO=URL override upstream repo URL
#   DOTFILES_DIR=PATH override local source directory

set -uo pipefail

REPO="${DOTFILES_REPO:-https://github.com/martinzachariassen/dotfiles.git}"
SOURCE_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_BACKUP="${SKIP_BACKUP:-0}"
ASSUME_YES="${YES:-0}"
CONFIGURE_ONLY=0
RESET_BREW_REQUESTED=0
MIRROR_BREW_REQUESTED=0

FEATURE_KEYS=(macApps ai)

usage() {
    cat <<EOF
Usage: bash install.sh [--configure-only] [--reset-brew] [--mirror-brew]

Flags:
  --configure-only  only update chezmoi data and apply dotfiles
  --reset-brew      uninstall all current Homebrew formulae/casks before apply
  --mirror-brew     remove Homebrew formulae/casks not in the active Brewfiles

Environment:
  DRY_RUN=1         print state-changing commands without running them
  YES=1             accept recommended defaults (does not reset or mirror Homebrew)
  SKIP_BACKUP=1     do not snapshot pre-existing legacy dotfiles
  DOTFILES_REPO=URL override upstream repo URL
  DOTFILES_DIR=PATH override local source directory
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --configure-only) CONFIGURE_ONLY=1 ;;
        --reset-brew) RESET_BREW_REQUESTED=1 ;;
        --mirror-brew) MIRROR_BREW_REQUESTED=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "install.sh: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

if [ "$RESET_BREW_REQUESTED" = "1" ] && [ "$MIRROR_BREW_REQUESTED" = "1" ]; then
    echo "install.sh: choose either --reset-brew or --mirror-brew, not both" >&2
    exit 1
fi

if [ -t 1 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'
    GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RED=$'\033[31m'
    CYAN=$'\033[36m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; GREEN=""; YELLOW=""; BLUE=""; RED=""; CYAN=""; RESET=""
fi

say()   { printf "%s  %s\n" "${CYAN}│${RESET}" "$1"; }
ok()    { printf "%s  %s✓%s %s\n" "${CYAN}│${RESET}" "$GREEN" "$RESET" "$1"; }
info()  { printf "%s  %s→%s %s\n" "${CYAN}│${RESET}" "$BLUE" "$RESET" "$1"; }
warn()  { printf "%s  %s!%s %s\n" "${CYAN}│${RESET}" "$YELLOW" "$RESET" "$1"; }
fail()  { printf "%s  %s✗%s %s\n" "${CYAN}│${RESET}" "$RED" "$RESET" "$1"; }
dim()   { printf "%s  %s%s%s\n" "${CYAN}│${RESET}" "$DIM" "$1" "$RESET"; }
hr()    { printf "%s\n" "${CYAN}│${RESET}"; }

require_non_root() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        fail "do not run this installer with sudo"
        say "Run it as your normal macOS user:"
        dim "    curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash"
        say "Homebrew and macOS steps will ask for your sudo password only when they need it."
        exit 1
    fi
}

setting() {
    local label="$1" value="$2"
    printf "%s    %-18s %s\n" "${CYAN}│${RESET}" "$label" "$value"
}

bool_label() {
    case "${1:-false}" in
        true|1|yes) printf 'yes' ;;
        *) printf 'no' ;;
    esac
}

phase_open() {
    local title="$1"
    printf "%s\n" "${CYAN}│${RESET}"
    printf "%s  %s%s%s\n" "${CYAN}◆${RESET}" "$BOLD" "$title" "$RESET"
    printf "%s\n" "${CYAN}│${RESET}"
}

phase_close() {
    local title="$1"
    printf "%s\n" "${CYAN}│${RESET}"
    printf "%s  %s%s complete%s\n" "${GREEN}✓${RESET}" "$DIM" "$title" "$RESET"
}

run() {
    if [ "$DRY_RUN" = "1" ]; then
        local display=() arg
        for arg in "$@"; do
            case "$arg" in
                --promptString=signingKey=*) display+=("--promptString=signingKey=<set>") ;;
                *) display+=("$arg") ;;
            esac
        done
        printf "%s    %sdry-run $%s %s\n" "${CYAN}│${RESET}" "$DIM" "$RESET" "${display[*]}"
    else
        "$@"
    fi
}

LONG_STEP_PID=""

start_long_step() {
    [ "$DRY_RUN" = "1" ] && return 0
    local label="$1" parent_pid=$$ start_ts
    start_ts="$(date +%s)"
    (
        sleep 30
        while kill -0 "$parent_pid" 2>/dev/null; do
            local now elapsed mins secs
            now="$(date +%s)"
            elapsed=$((now - start_ts))
            mins=$((elapsed / 60))
            secs=$((elapsed % 60))
            printf "%s    %s... still working on %s - %dm%02ds elapsed%s\n" "${CYAN}│${RESET}" "$DIM" "$label" "$mins" "$secs" "$RESET"
            sleep 30
        done
    ) &
    LONG_STEP_PID=$!
}

stop_long_step() {
    [ -n "$LONG_STEP_PID" ] && kill "$LONG_STEP_PID" 2>/dev/null
    wait "$LONG_STEP_PID" 2>/dev/null || true
    LONG_STEP_PID=""
}

cleanup_background_jobs() {
    stop_long_step
    stop_sudo_keepalive
}

trap cleanup_background_jobs EXIT

timed_run() {
    local label="$1"
    shift
    local start_ts end_ts elapsed mins secs rc
    start_ts="$(date +%s)"
    start_long_step "$label"
    rc=0
    run "$@" || rc=$?
    stop_long_step
    end_ts="$(date +%s)"
    elapsed=$((end_ts - start_ts))
    mins=$((elapsed / 60))
    secs=$((elapsed % 60))
    if [ "$rc" -eq 0 ]; then
        ok "$label finished in ${mins}m${secs}s"
    else
        fail "$label failed after ${mins}m${secs}s"
        return "$rc"
    fi
}

SUDO_KEEPALIVE_PID=""

stop_sudo_keepalive() {
    [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
}

start_sudo_keepalive() {
    [ "$DRY_RUN" = "1" ] && return 0
    local parent_pid=$$
    (
        while kill -0 "$parent_pid" 2>/dev/null; do
            sudo -n true 2>/dev/null || exit
            sleep 60
        done
    ) &
    SUDO_KEEPALIVE_PID=$!
}

cache_sudo_for_homebrew() {
    [ "$DRY_RUN" = "1" ] && return 0
    sudo -n true 2>/dev/null && return 0

    if ! have_tty; then
        fail "Homebrew needs sudo on a fresh Mac, but no terminal is available for the password prompt"
        say "Run the installer from an interactive terminal:"
        dim "    curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash"
        exit 1
    fi

    hr
    say "${BOLD}Homebrew needs admin access.${RESET}"
    say "Enter your macOS password once so Homebrew can create /opt/homebrew."
    exec </dev/tty
    sleep 0.2
    if ! sudo -v -p "[install.sh] sudo password: "; then
        fail "could not cache sudo credentials for Homebrew"
        exit 1
    fi
    ok "sudo cached for Homebrew"
}

have_tty() {
    ( exec </dev/tty >/dev/tty ) 2>/dev/null
}

prompt_read() {
    local __out="$1" prompt="$2" response
    printf "%s  %s" "${CYAN}│${RESET}" "$prompt" > /dev/tty
    IFS= read -r response < /dev/tty || response=""
    printf -v "$__out" '%s' "$response"
}

prompt_text() {
    local __out="$1" title="$2" default="${3:-}" hint="${4:-}" answer

    if ! have_tty || [ "$ASSUME_YES" = "1" ]; then
        printf -v "$__out" '%s' "$default"
        printf "%s  %s%s:%s %s%s%s\n" "${GREEN}✓${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "${default:-<blank>}" "$RESET"
        return
    fi

    printf "%s  %s%s%s\n" "${CYAN}◆${RESET}" "$BOLD" "$title" "$RESET" > /dev/tty
    [ -n "$hint" ] && printf "%s  %s%s%s\n" "${CYAN}│${RESET}" "$DIM" "$hint" "$RESET" > /dev/tty
    if [ -n "$default" ]; then
        prompt_read answer "Current: ${BOLD}$default${RESET}. Enter new value or leave blank to keep: "
        [ -z "$answer" ] && answer="$default"
    else
        prompt_read answer "Enter value, or leave blank to skip: "
    fi
    printf "%s  %s%s:%s %s%s%s\n" "${GREEN}✓${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "${answer:-<blank>}" "$RESET"
    printf -v "$__out" '%s' "$answer"
}

prompt_confirm() {
    local __out="$1" title="$2" default_yes="${3:-1}" answer default_label result
    [ "$default_yes" = "1" ] && default_label="Y/n" || default_label="y/N"

    if ! have_tty || [ "$ASSUME_YES" = "1" ]; then
        [ "$default_yes" = "1" ] && result=true || result=false
        printf -v "$__out" '%s' "$result"
        printf "%s  %s%s:%s %s%s%s %s(default)%s\n" \
            "${GREEN}✓${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$([ "$result" = true ] && echo yes || echo no)" "$RESET" "$DIM" "$RESET"
        return
    fi

    while :; do
        prompt_read answer "${BOLD}${title}${RESET} [$default_label] "
        case "${answer:-default}" in
            default)
                [ "$default_yes" = "1" ] && result=true || result=false
                break ;;
            y|Y|yes|YES) result=true; break ;;
            n|N|no|NO) result=false; break ;;
            *) warn "answer y or n" ;;
        esac
    done
    printf -v "$__out" '%s' "$result"
    printf "%s  %s%s:%s %s%s%s\n" \
        "${GREEN}✓${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$([ "$result" = true ] && echo yes || echo no)" "$RESET"
}

prompt_choice() {
    local __out="$1" title="$2" default="$3"
    shift 3
    local opts=("$@") n=$# i answer value label

    if ! have_tty || [ "$ASSUME_YES" = "1" ]; then
        printf -v "$__out" '%s' "$default"
        printf "%s  %s%s:%s %s%s%s %s(default)%s\n" \
            "${GREEN}✓${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$default" "$RESET" "$DIM" "$RESET"
        return
    fi

    printf "%s  %s%s%s\n" "${CYAN}◆${RESET}" "$BOLD" "$title" "$RESET" > /dev/tty
    for ((i=0; i<n; i++)); do
        value="${opts[$i]%%|*}"
        label="${opts[$i]#*|}"
        if [ "$value" = "$default" ]; then
            printf "%s    %d. %s %s%s(current)%s\n" "${CYAN}│${RESET}" $((i + 1)) "$label" "$DIM" "$RESET" "$DIM" > /dev/tty
        else
            printf "%s    %d. %s\n" "${CYAN}│${RESET}" $((i + 1)) "$label" > /dev/tty
        fi
    done

    while :; do
        prompt_read answer "Choose 1-$n, or leave blank for ${BOLD}$default${RESET}: "
        [ -z "$answer" ] && { printf -v "$__out" '%s' "$default"; break; }
        case "$answer" in
            ''|*[!0-9]*) warn "enter a number from 1 to $n" ;;
            *)
                if [ "$answer" -ge 1 ] && [ "$answer" -le "$n" ]; then
                    value="${opts[$((answer - 1))]%%|*}"
                    printf -v "$__out" '%s' "$value"
                    break
                fi
                warn "enter a number from 1 to $n"
                ;;
        esac
    done
    printf "%s  %s%s:%s %s%s%s\n" "${GREEN}✓${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "${!__out}" "$RESET"
}

prompt_continue_or_customize() {
    local __out="$1" title="$2" answer

    if ! have_tty || [ "$ASSUME_YES" = "1" ]; then
        printf -v "$__out" '%s' "recommended"
        printf "%s  %s%s:%s %srecommended%s %s(default)%s\n" \
            "${GREEN}✓${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$RESET" "$DIM" "$RESET"
        return
    fi

    printf "%s  %s%s%s\n" "${CYAN}◆${RESET}" "$BOLD" "$title" "$RESET" > /dev/tty
    printf "%s    1. Continue with recommended setup\n" "${CYAN}│${RESET}" > /dev/tty
    printf "%s    2. Customize packages, signing, cleanup, and migration\n" "${CYAN}│${RESET}" > /dev/tty

    while :; do
        prompt_read answer "Press Enter for recommended, or choose 1-2: "
        case "${answer:-1}" in
            1)
                printf -v "$__out" '%s' "recommended"
                break ;;
            2)
                printf -v "$__out" '%s' "custom"
                break ;;
            *) warn "enter 1 or 2" ;;
        esac
    done
    printf "%s  %s%s:%s %s%s%s\n" "${GREEN}✓${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "${!__out}" "$RESET"
}

prompt_phrase() {
    local phrase="$1" answer
    if [ "$ASSUME_YES" = "1" ]; then
        return 0
    fi
    if ! have_tty; then
        return 1
    fi
    prompt_read answer "Type ${BOLD}$phrase${RESET} to confirm: "
    [ "$answer" = "$phrase" ]
}

json_string() {
    local json="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$json" | jq -r --arg key "$key" '.[$key] // empty'
    else
        printf '%s\n' "$json" \
            | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
            | sed '/^$/d' \
            | tail -1
    fi
}

json_bool() {
    local json="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$json" | jq -r --arg key "$key" '.[$key] // .features[$key] // empty'
    else
        printf '%s\n' "$json" \
            | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p" \
            | tail -1
    fi
}

toml_string() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$file" | tail -1
}

toml_bool() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\\(true\\|false\\)[[:space:]]*$/\1/p" "$file" | tail -1
}

feature_default() {
    case "$1" in
        macApps) printf 'true' ;;
        ai) printf 'false' ;;
        *) printf 'false' ;;
    esac
}

load_existing_answers() {
    EXISTING_NAME=""
    EXISTING_EMAIL=""
    EXISTING_SIGNINGKEY=""
    EXISTING_PROFILE="personal"
    EXISTING_USE_OP="true"
    EXISTING_FEAT_macApps="true"
    EXISTING_FEAT_ai="false"

    if command -v chezmoi >/dev/null 2>&1 && [ -f "$HOME/.config/chezmoi/chezmoi.toml" ]; then
        local data_json key val
        data_json="$(chezmoi data --format=json 2>/dev/null || echo '{}')"
        EXISTING_NAME="$(json_string "$data_json" "name")"
        EXISTING_EMAIL="$(json_string "$data_json" "email")"
        EXISTING_SIGNINGKEY="$(json_string "$data_json" "signingKey")"
        EXISTING_PROFILE="$(json_string "$data_json" "profile")"
        EXISTING_USE_OP="$(json_bool "$data_json" "useOnePassword")"
        for key in "${FEATURE_KEYS[@]}"; do
            val="$(json_bool "$data_json" "$key")"
            eval "EXISTING_FEAT_${key}=\"\${val:-$(feature_default "$key")}\""
        done
    elif [ -f "$HOME/.config/chezmoi/chezmoi.toml" ]; then
        local cfg="$HOME/.config/chezmoi/chezmoi.toml"
        EXISTING_NAME="$(toml_string "$cfg" "name")"
        EXISTING_EMAIL="$(toml_string "$cfg" "email")"
        EXISTING_SIGNINGKEY="$(toml_string "$cfg" "signingKey")"
        EXISTING_PROFILE="$(toml_string "$cfg" "profile")"
        EXISTING_USE_OP="$(toml_bool "$cfg" "useOnePassword")"
        EXISTING_FEAT_macApps="$(toml_bool "$cfg" "macApps")"
        EXISTING_FEAT_ai="$(toml_bool "$cfg" "ai")"
    fi

    EXISTING_NAME="${EXISTING_NAME:-$(git config --global user.name 2>/dev/null || echo '')}"
    EXISTING_EMAIL="${EXISTING_EMAIL:-$(git config --global user.email 2>/dev/null || echo '')}"
    EXISTING_PROFILE="${EXISTING_PROFILE:-personal}"
    EXISTING_USE_OP="${EXISTING_USE_OP:-true}"
    EXISTING_FEAT_macApps="${EXISTING_FEAT_macApps:-true}"
    EXISTING_FEAT_ai="${EXISTING_FEAT_ai:-false}"
}

banner() {
    printf "\n"
    printf "%s\n" "${CYAN}╭────────────────────────────────────────────────────────────╮${RESET}"
    printf "%s  %sDotfiles Setup%s                                             %s\n" "${CYAN}│${RESET}" "$BOLD" "$RESET" "${CYAN}│${RESET}"
    printf "%s  Plug-and-play macOS workstation bootstrap.                  %s\n" "${CYAN}│${RESET}" "${CYAN}│${RESET}"
    printf "%s\n" "${CYAN}╰────────────────────────────────────────────────────────────╯${RESET}"
    if [ "$DRY_RUN" = "1" ]; then
        printf "%s  %sDry run:%s no changes will be made.\n" "${CYAN}│${RESET}" "$YELLOW$BOLD" "$RESET"
    fi
    if [ "$ASSUME_YES" = "1" ]; then
        printf "%s  %sYes mode:%s recommended defaults accepted. Homebrew cleanup stays off unless flagged.\n" "${CYAN}│${RESET}" "$YELLOW$BOLD" "$RESET"
    fi
    if [ "$CONFIGURE_ONLY" = "1" ]; then
        printf "%s  %sConfigure only:%s update profile, identity, features, then apply.\n" "${CYAN}│${RESET}" "$YELLOW$BOLD" "$RESET"
    fi
    printf "%s  The default path asks for identity, profile, and optional git signing.\n" "${CYAN}│${RESET}"
    printf "%s  Advanced cleanup and feature toggles stay available when you need them.\n" "${CYAN}│${RESET}"
    if have_tty && [ "$ASSUME_YES" != "1" ]; then
        local _
        printf "%s\n" "${CYAN}│${RESET}"
        prompt_read _ "Press Enter to begin "
    fi
}

probe() {
    phase_open "1/5 - Check this Mac"

    if [ "$(uname -s)" != "Darwin" ]; then
        fail "this installer only supports macOS (current OS: $(uname -s))"
        exit 1
    fi

    PROBE_ARCH="$(uname -m)"
    PROBE_OS_VER="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
    if [ "$PROBE_ARCH" = "arm64" ]; then
        ok "macOS $PROBE_OS_VER on Apple Silicon"
    else
        warn "macOS $PROBE_OS_VER on Intel - this repo targets Apple Silicon"
    fi

    if xcode-select -p >/dev/null 2>&1; then ok "Xcode Command Line Tools present"; else info "Xcode CLT missing - setup will open Apple's installer"; fi
    if command -v brew >/dev/null 2>&1; then ok "Homebrew at $(command -v brew)"; else info "Homebrew missing - setup will install it"; fi
    if command -v chezmoi >/dev/null 2>&1; then ok "$(chezmoi --version 2>/dev/null | head -1)"; else info "chezmoi missing - setup will install it"; fi

    PROBE_CHEZMOI_CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
    if [ -f "$PROBE_CHEZMOI_CONFIG" ]; then ok "existing chezmoi config found"; else info "no existing chezmoi config"; fi
    if [ -d "$SOURCE_DIR/.git" ]; then PROBE_REPO_CLONED=1; ok "repo already cloned at $SOURCE_DIR"; else PROBE_REPO_CLONED=0; info "repo will be cloned to $SOURCE_DIR"; fi
    if [ -d /Applications/1Password.app ]; then ok "1Password.app installed"; else info "1Password.app not installed yet"; fi

    PROBE_LEGACY_FILES=()
    for f in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.gitconfig" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile"; do
        if [ -f "$f" ] && [ ! -L "$f" ] && [ -s "$f" ]; then
            PROBE_LEGACY_FILES+=("$f")
        fi
    done
    if [ ${#PROBE_LEGACY_FILES[@]} -gt 0 ]; then
        warn "found ${#PROBE_LEGACY_FILES[@]} legacy shell/git file(s) that can shadow the managed XDG files"
        for f in "${PROBE_LEGACY_FILES[@]}"; do dim "    $f"; done
    else
        ok "no legacy shell/git files in \$HOME"
    fi

    if [ -d "$HOME/.oh-my-zsh" ]; then PROBE_OMZ=1; warn "oh-my-zsh found at ~/.oh-my-zsh"; else PROBE_OMZ=0; fi

    phase_close "Mac check"
}

choices() {
    phase_open "2/5 - Choose setup"
    load_existing_answers

    say "${BOLD}Essentials first.${RESET} Press Enter to keep any detected value."
    hr

    prompt_choice CHOICE_PROFILE "Profile" "$EXISTING_PROFILE" \
        "personal|personal - personal extras only" \
        "work|work - work extras only" \
        "both|both - personal and work extras"

    prompt_text CHOICE_NAME "Full name" "$EXISTING_NAME" "Written to ~/.config/git/config as git user.name."
    prompt_text CHOICE_EMAIL "Git email" "$EXISTING_EMAIL" "Written to ~/.config/git/config as git user.email. GitHub noreply addresses are fine."

    CHOICE_USE_OP="${EXISTING_USE_OP:-true}"
    CHOICE_SIGNINGKEY="$EXISTING_SIGNINGKEY"
    CHOICE_FEAT_macApps="${EXISTING_FEAT_macApps:-true}"
    CHOICE_FEAT_ai="${EXISTING_FEAT_ai:-false}"
    CHOICE_RESET_BREW=false
    CHOICE_MIRROR_BREW=false
    CHOICE_BACKUP_LEGACY=true
    CHOICE_REMOVE_OMZ=false

    if [ "$CONFIGURE_ONLY" != "1" ] && [ "$PROBE_OMZ" = "1" ]; then
        CHOICE_REMOVE_OMZ=true
    fi

    hr
    say "${BOLD}Recommended setup${RESET}"
    setting "1Password" "$(bool_label "$CHOICE_USE_OP")"
    setting "Mac apps" "$(bool_label "$CHOICE_FEAT_macApps")"
    setting "Local AI" "$(bool_label "$CHOICE_FEAT_ai")"
    setting "Homebrew cleanup" "keep local packages"
    if [ "$CONFIGURE_ONLY" != "1" ] && [ ${#PROBE_LEGACY_FILES[@]} -gt 0 ]; then
        setting "Legacy files" "back up, then remove shadowing files"
    fi
    if [ "$CONFIGURE_ONLY" != "1" ] && [ "$PROBE_OMZ" = "1" ]; then
        setting "oh-my-zsh" "uninstall before applying plain zsh"
    fi
    dim "    Choose customize if you want to change package extras, signing, or cleanup."

    CHOICE_SETUP_MODE="recommended"
    if [ "$RESET_BREW_REQUESTED" = "1" ] || [ "$MIRROR_BREW_REQUESTED" = "1" ]; then
        CHOICE_SETUP_MODE="custom"
    else
        prompt_continue_or_customize CHOICE_SETUP_MODE "Setup style"
    fi

    if [ "$CHOICE_SETUP_MODE" = "custom" ]; then
        hr
        say "${BOLD}Advanced options${RESET}"
        prompt_confirm CHOICE_USE_OP "Use 1Password for SSH auth and git signing?" "$([ "$CHOICE_USE_OP" = "true" ] && echo 1 || echo 0)"
        if [ "$CHOICE_USE_OP" = "true" ]; then
            prompt_text CHOICE_SIGNINGKEY "SSH signing public key" "$EXISTING_SIGNINGKEY" "Paste the public key line from 1Password, or leave blank to set it later."
        else
            CHOICE_SIGNINGKEY=""
        fi

        prompt_confirm CHOICE_FEAT_macApps "Install workstation Mac apps?" "$([ "$CHOICE_FEAT_macApps" = "true" ] && echo 1 || echo 0)"
        prompt_confirm CHOICE_FEAT_ai "Install local AI tooling (Ollama, llm)?" "$([ "$CHOICE_FEAT_ai" = "true" ] && echo 1 || echo 0)"
    elif [ "$CHOICE_USE_OP" != "true" ]; then
        CHOICE_SIGNINGKEY=""
    elif [ -z "$CHOICE_SIGNINGKEY" ]; then
        prompt_text CHOICE_SIGNINGKEY "Git signing public key (optional)" "" "Copy the public key line from 1Password. Leave blank to set it later."
    fi

    if [ "$CONFIGURE_ONLY" != "1" ]; then
        if [ "$RESET_BREW_REQUESTED" = "1" ]; then
            CHOICE_RESET_BREW=true
            warn "Homebrew reset requested by --reset-brew"
        elif [ "$MIRROR_BREW_REQUESTED" = "1" ]; then
            CHOICE_MIRROR_BREW=true
            warn "Homebrew mirror requested by --mirror-brew"
        elif [ "$CHOICE_SETUP_MODE" = "custom" ] && command -v brew >/dev/null 2>&1; then
            local brew_cleanup_mode
            warn "Optional Homebrew cleanup."
            dim "    Mirror removes packages not present in the active Brewfiles. Reset removes everything first, then reinstalls."
            prompt_choice brew_cleanup_mode "Homebrew cleanup mode" "keep" \
                "keep|keep - leave locally installed packages alone" \
                "mirror|mirror - remove packages not in the selected Brewfiles" \
                "reset|reset - uninstall all Homebrew packages before reinstalling"
            case "$brew_cleanup_mode" in
                mirror) CHOICE_MIRROR_BREW=true ;;
                reset) CHOICE_RESET_BREW=true ;;
            esac
        fi
    fi

    if [ "$CHOICE_SETUP_MODE" = "custom" ] && [ "$CONFIGURE_ONLY" != "1" ] && [ ${#PROBE_LEGACY_FILES[@]} -gt 0 ]; then
        prompt_confirm CHOICE_BACKUP_LEGACY "Back up legacy files and remove originals?" 1
    fi
    if [ "$CHOICE_SETUP_MODE" = "custom" ] && [ "$CONFIGURE_ONLY" != "1" ] && [ "$PROBE_OMZ" = "1" ]; then
        prompt_confirm CHOICE_REMOVE_OMZ "Uninstall oh-my-zsh before applying dotfiles?" 1
    fi

    phase_close "Setup choices"
}

confirm_phase() {
    phase_open "3/5 - Review plan"

    say "${BOLD}This is what will be applied.${RESET}"
    setting "Setup style" "${CHOICE_SETUP_MODE:-recommended}"
    setting "Profile" "$CHOICE_PROFILE"
    setting "Name" "${CHOICE_NAME:-<blank>}"
    setting "Email" "${CHOICE_EMAIL:-<blank>}"
    setting "1Password" "$(bool_label "$CHOICE_USE_OP")"
    if [ -n "$CHOICE_SIGNINGKEY" ]; then
        setting "Signing key" "${CHOICE_SIGNINGKEY:0:44}..."
    else
        setting "Signing key" "<none - set later>"
    fi
    setting "Mac apps" "$(bool_label "$CHOICE_FEAT_macApps")"
    setting "Local AI" "$(bool_label "$CHOICE_FEAT_ai")"
    setting "Repo" "$REPO"
    setting "Source dir" "$SOURCE_DIR"
    if [ "$CONFIGURE_ONLY" != "1" ]; then
        setting "Legacy backup" "$(bool_label "$CHOICE_BACKUP_LEGACY")"
        setting "Remove OMZ" "$(bool_label "$CHOICE_REMOVE_OMZ")"
        setting "Reset Homebrew" "$(bool_label "$CHOICE_RESET_BREW")"
        setting "Mirror Homebrew" "$(bool_label "$CHOICE_MIRROR_BREW")"
    fi

    if [ "$CHOICE_RESET_BREW" = "true" ] || [ "$CHOICE_MIRROR_BREW" = "true" ]; then
        hr
        if [ "$CHOICE_RESET_BREW" = "true" ]; then
            warn "Homebrew reset is destructive."
            dim "    It will uninstall all formulae and casks currently known to brew before reinstalling this repo's Brewfile set."
            if ! prompt_phrase "RESET BREW"; then
                fail "Homebrew reset was selected but the confirmation phrase was not entered"
                exit 1
            fi
        else
            warn "Homebrew mirror removes local packages outside the selected Brewfiles."
            dim "    Active set: core Brewfile, enabled feature Brewfiles, and the selected profile Brewfile(s)."
            if ! prompt_phrase "MIRROR BREW"; then
                fail "Homebrew mirror was selected but the confirmation phrase was not entered"
                exit 1
            fi
        fi
    fi

    hr
    local proceed
    if [ "$CONFIGURE_ONLY" = "1" ]; then
        prompt_confirm proceed "Apply this configuration?" 1
    else
        prompt_confirm proceed "Proceed with installation?" 1
    fi
    if [ "$proceed" != "true" ]; then
        info "aborted - nothing changed"
        phase_close "Review"
        exit 0
    fi

    phase_close "Review"
}

reset_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        info "Homebrew reset requested, but brew is not installed yet"
        return 0
    fi

    phase_open "Homebrew reset"
    warn "uninstalling all existing Homebrew casks and formulae"

    local casks formulae
    casks="$(brew list --cask 2>/dev/null || true)"
    formulae="$(brew list --formula 2>/dev/null || true)"

    if [ -n "$casks" ]; then
        while IFS= read -r cask; do
            [ -n "$cask" ] || continue
            info "uninstalling cask $cask"
            run brew uninstall --cask --force "$cask" || warn "could not uninstall cask $cask"
        done <<EOF_CASKS
$casks
EOF_CASKS
    else
        ok "no casks to uninstall"
    fi

    if [ -n "$formulae" ]; then
        while IFS= read -r formula; do
            [ -n "$formula" ] || continue
            info "uninstalling formula $formula"
            run brew uninstall --formula --force --ignore-dependencies "$formula" || warn "could not uninstall formula $formula"
        done <<EOF_FORMULAE
$formulae
EOF_FORMULAE
    else
        ok "no formulae to uninstall"
    fi

    run brew autoremove || true
    run brew cleanup --prune=all || true
    hash -r 2>/dev/null || true
    ok "Homebrew reset complete; Brewfiles will reinstall the managed set during chezmoi apply"
    phase_close "Homebrew reset"
}

active_brewfiles() {
    printf '%s\n' "$SOURCE_DIR/Brewfile"
    if [ "${CHOICE_FEAT_macApps:-true}" = "true" ]; then
        printf '%s\n' "$SOURCE_DIR/brewfiles/Brewfile.mac-apps"
    fi
    if [ "${CHOICE_FEAT_ai:-false}" = "true" ]; then
        printf '%s\n' "$SOURCE_DIR/brewfiles/Brewfile.ai"
    fi
    case "${CHOICE_PROFILE:-personal}" in
        personal|both) printf '%s\n' "$SOURCE_DIR/brewfiles/Brewfile.personal" ;;
    esac
    case "${CHOICE_PROFILE:-personal}" in
        work|both) printf '%s\n' "$SOURCE_DIR/brewfiles/Brewfile.work" ;;
    esac
}

mirror_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        info "Homebrew mirror requested, but brew is not installed"
        return 0
    fi

    phase_open "Homebrew mirror"
    warn "removing Homebrew packages that are not in the active Brewfiles"

    local merged_brewfile file
    merged_brewfile="$(mktemp)"
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        if [ -f "$file" ]; then
            dim "    keeping entries from $(basename "$file")"
            {
                printf '\n# ---- %s ----\n' "$(basename "$file")"
                sed '/^[[:space:]]*$/d' "$file"
            } >> "$merged_brewfile"
        else
            warn "expected Brewfile missing: $file"
        fi
    done <<EOF_BREWFILES
$(active_brewfiles)
EOF_BREWFILES

    if [ ! -s "$merged_brewfile" ]; then
        rm -f "$merged_brewfile"
        fail "no Brewfiles available for mirror cleanup"
        exit 1
    fi

    if ! run brew bundle cleanup --force --file="$merged_brewfile"; then
        rm -f "$merged_brewfile"
        fail "Homebrew mirror cleanup failed"
        exit 1
    fi
    rm -f "$merged_brewfile"
    run brew autoremove || true
    run brew cleanup || true
    ok "Homebrew now mirrors the selected Brewfile set"
    phase_close "Homebrew mirror"
}

ensure_homebrew_packages() {
    [ "$DRY_RUN" = "1" ] && return 0
    command -v brew >/dev/null 2>&1 || { fail "brew is not on PATH; cannot install Brewfile packages"; exit 1; }

    phase_open "Homebrew packages"
    say "${BOLD}Verifying active Brewfiles.${RESET}"

    local file label missing=0
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        label="$(basename "$file")"
        if [ ! -f "$file" ]; then
            fail "expected Brewfile missing: $file"
            exit 1
        fi
        if brew bundle check --file="$file" >/dev/null 2>&1; then
            ok "$label already satisfied"
        else
            missing=1
            info "$label has missing packages"
            cache_sudo_for_homebrew
            start_sudo_keepalive
            if ! timed_run "$label install" brew bundle install --file="$file"; then
                stop_sudo_keepalive
                exit 1
            fi
            stop_sudo_keepalive
        fi
    done <<EOF_BREWFILES
$(active_brewfiles)
EOF_BREWFILES

    if [ "$missing" = "0" ]; then
        ok "all selected Brewfiles are installed"
    else
        ok "selected Brewfiles installed"
    fi
    phase_close "Homebrew packages"
}

install_xcode_clt() {
    info "Xcode Command Line Tools"
    if ! xcode-select -p >/dev/null 2>&1; then
        info "opening Apple's Command Line Tools installer"
        run xcode-select --install || true
        if [ "$DRY_RUN" != "1" ]; then
            dim "    Complete Apple's installer dialog if it is still open. Fresh Macs can spend 20-60 minutes here."
            printf "%s    %swaiting for CLT install to complete" "${CYAN}|${RESET}" "$DIM"
            local i
            for i in $(seq 1 720); do
                if xcode-select -p >/dev/null 2>&1; then printf "%s\n" "$RESET"; break; fi
                if [ $((i % 12)) -eq 0 ]; then
                    printf "%s\n" "$RESET"
                    dim "    still waiting for Xcode CLT - $((i / 12))m elapsed"
                    printf "%s    %swaiting" "${CYAN}|${RESET}" "$DIM"
                else
                    printf "."
                fi
                sleep 5
            done
            if ! xcode-select -p >/dev/null 2>&1; then
                printf "%s\n" "$RESET"
                fail "Xcode CLT install timed out after 60 minutes; re-run the installer after it finishes"
                exit 1
            fi
        fi
    fi
    ok "Xcode CLT at $(xcode-select -p 2>/dev/null || echo '<dry-run>')"
}

install_homebrew() {
    info "Homebrew"
    if ! command -v brew >/dev/null 2>&1; then
        cache_sudo_for_homebrew
        dim "    Apple's CLT install may continue in the background; Homebrew can be slow while it waits for that toolchain."
        start_sudo_keepalive
        if ! timed_run "Homebrew installer" install_homebrew_script; then
            stop_sudo_keepalive
            exit 1
        fi
        stop_sudo_keepalive
    fi
    if [ "$DRY_RUN" != "1" ] && [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    if [ "$DRY_RUN" != "1" ] && ! command -v brew >/dev/null 2>&1; then
        fail "Homebrew installer finished, but brew is still not on PATH"
        exit 1
    fi
    ok "Homebrew at $(command -v brew 2>/dev/null || echo '<dry-run>')"
}

install_homebrew_script() {
    local installer rc
    installer="$(mktemp)"
    if ! curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
        rm -f "$installer"
        return 1
    fi
    NONINTERACTIVE=1 /bin/bash "$installer"
    rc=$?
    rm -f "$installer"
    return "$rc"
}

configure_chezmoi() {
    info "Configuring chezmoi with the selected setup"
    run mkdir -p "$HOME/.config/chezmoi" || exit 1

    local init_flags key var
    init_flags=(
        "--source=$SOURCE_DIR"
        "--promptString=name=$CHOICE_NAME"
        "--promptString=email=$CHOICE_EMAIL"
        "--promptString=signingKey=$CHOICE_SIGNINGKEY"
        "--promptChoice=profile=$CHOICE_PROFILE"
        "--promptBool=useOnePassword=$CHOICE_USE_OP"
    )
    for key in "${FEATURE_KEYS[@]}"; do
        var="CHOICE_FEAT_${key}"
        init_flags+=("--promptBool=features.${key}=${!var}")
    done
    run chezmoi init "${init_flags[@]}" || exit 1
    ok "chezmoi configured"
}

create_developer_directories() {
    info "Developer directories"
    run mkdir -p \
        "$HOME/Developer/work" \
        "$HOME/Developer/personal" \
        "$HOME/Developer/learning" \
        "$HOME/Developer/experiments" \
        "$HOME/Developer/tools" \
        "$HOME/Developer/scripts" \
        "$HOME/Developer/archive" || exit 1
    ok "Developer directory structure ready"
}

backup_legacy_files() {
    [ "$SKIP_BACKUP" = "1" ] && return 0
    [ "${CHOICE_BACKUP_LEGACY:-true}" = "true" ] || return 0
    [ ${#PROBE_LEGACY_FILES[@]} -gt 0 ] || return 0

    BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
    info "backing up ${#PROBE_LEGACY_FILES[@]} legacy file(s) to $BACKUP_DIR"
    local f rel
    for f in "${PROBE_LEGACY_FILES[@]}"; do
        rel="${f#"$HOME"/}"
        run mkdir -p "$BACKUP_DIR/$(dirname "$rel")" || exit 1
        run cp -p "$f" "$BACKUP_DIR/$rel" || exit 1
        run rm -f "$f" || exit 1
    done
    ok "legacy files backed up and removed"
}

execute() {
    phase_open "4/5 - Install and apply"
    if [ "$CONFIGURE_ONLY" != "1" ]; then
        say "${BOLD}Fresh Mac bootstrap can pause on Apple and Homebrew installers.${RESET}"
        setting "4.1" "prepare directories and legacy files"
        setting "4.2" "Xcode Command Line Tools"
        setting "4.3" "Homebrew and chezmoi"
        setting "4.4" "clone dotfiles repo"
        setting "4.5" "install packages, then apply dotfiles"
        dim "    Long external installers print a 30-second heartbeat while they run."
        hr
    fi

    if [ "$CONFIGURE_ONLY" = "1" ]; then
        if [ ! -d "$SOURCE_DIR/.git" ]; then fail "configure-only requires an existing repo at $SOURCE_DIR"; exit 1; fi
        if ! command -v chezmoi >/dev/null 2>&1; then fail "configure-only requires chezmoi on PATH"; exit 1; fi
        create_developer_directories
        configure_chezmoi
        ensure_homebrew_packages
        info "Applying dotfiles for updated profile/features"
        run chezmoi apply --force || exit 1
        ok "chezmoi apply complete"
        ensure_homebrew_packages
        phase_close "Install and apply"
        return
    fi

    backup_legacy_files
    create_developer_directories
    if [ "${CHOICE_REMOVE_OMZ:-false}" = "true" ] && [ -d "$HOME/.oh-my-zsh" ]; then
        info "uninstalling oh-my-zsh non-interactively"
        run bash -c 'yes | "$HOME/.oh-my-zsh/tools/uninstall.sh"' || warn "oh-my-zsh uninstaller errored; continuing"
    fi

    install_xcode_clt
    install_homebrew
    [ "$CHOICE_RESET_BREW" = "true" ] && reset_homebrew

    info "chezmoi"
    if ! command -v chezmoi >/dev/null 2>&1; then
        timed_run "chezmoi Homebrew install" brew install chezmoi || exit 1
    fi
    ok "chezmoi at $(command -v chezmoi 2>/dev/null || echo '<dry-run>')"

    info "Repository at $SOURCE_DIR"
    if [ ! -d "$SOURCE_DIR/.git" ]; then
        run mkdir -p "$(dirname "$SOURCE_DIR")" || exit 1
        timed_run "dotfiles repository clone" git clone "$REPO" "$SOURCE_DIR" || exit 1
    else
        ok "already cloned"
    fi

    configure_chezmoi

    ensure_homebrew_packages
    info "Applying dotfiles after package verification."
    run chezmoi apply --force || exit 1
    ok "chezmoi apply complete"
    ensure_homebrew_packages
    [ "$CHOICE_MIRROR_BREW" = "true" ] && mirror_homebrew
    phase_close "Install and apply"
}

self_test() {
    phase_open "5/5 - Verify"
    if [ "$DRY_RUN" = "1" ]; then
        ok "DRY-RUN: skipping checks"
        phase_close "Verify"
        return
    fi

    chmod -R go-w /opt/homebrew/share/zsh* 2>/dev/null || true

    _v() {
        local name="$1"; shift
        if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
    }
    _vf() {
        local name="$1" cmd="$2" out
        if out=$(eval "$cmd" 2>&1); then ok "$name"; else fail "$name - $out"; fi
    }

    say "${DIM}core${RESET}"
    _v "git" git --version
    _v "chezmoi" chezmoi --version
    _v "devbox" devbox version
    _vf "Nix store /nix" "[ -d /nix ]"
    _vf "nix-daemon running" "launchctl list 2>/dev/null | grep -Eq '(org\\.nixos|systems\\.determinate)\\.nix-daemon'"
    _v "starship" starship --version
    _v "zellij" zellij --version
    _v "lazygit" lazygit --version
    _v "direnv" direnv version
    _v "delta" delta --version
    _v "fzf" fzf --version
    if [ "${CHOICE_FEAT_ai:-false}" = "true" ]; then
        _v "ollama" ollama --version
        _v "llm" llm --version
    fi

    say "${DIM}functional${RESET}"
    _vf "chezmoi doctor passes" "! chezmoi doctor 2>&1 | grep -q '^error'"
    _vf "no legacy ~/.zshrc" "[ ! -f \"\$HOME/.zshrc\" ]"
    _vf "no legacy ~/.gitconfig" "[ ! -f \"\$HOME/.gitconfig\" ]"
    _vf "no legacy ~/.zprofile" "[ ! -f \"\$HOME/.zprofile\" ]"
    _vf "no legacy ~/.bash_profile" "[ ! -f \"\$HOME/.bash_profile\" ]"
    _vf "no legacy ~/.bashrc" "[ ! -f \"\$HOME/.bashrc\" ]"
    _vf "no legacy ~/.profile" "[ ! -f \"\$HOME/.profile\" ]"
    _vf "ZDOTDIR zshrc exists" "[ -f \"\$HOME/.config/zsh/.zshrc\" ]"

    [ "$CHOICE_USE_OP" = "true" ] && _vf "op-ssh-sign present" "[ -x /Applications/1Password.app/Contents/MacOS/op-ssh-sign ]"
    _vf "JetBrainsMono Nerd Font" "ls \"\$HOME/Library/Fonts\" /Library/Fonts 2>/dev/null | grep -qi 'JetBrainsMono.*Nerd' || ls /opt/homebrew/Caskroom/font-jetbrains-mono-nerd-font 2>/dev/null | grep -q ."

    say "${DIM}apps${RESET}"
    _v "Ghostty.app" test -d /Applications/Ghostty.app
    _v "VS Code.app" test -d "/Applications/Visual Studio Code.app"
    [ "$CHOICE_USE_OP" = "true" ] && _v "1Password.app" test -d /Applications/1Password.app

    say "${DIM}auth state (fix from Next steps if needed)${RESET}"
    if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then ok "gh authenticated"; else warn "gh not authenticated"; fi
    if command -v az >/dev/null && az account show >/dev/null 2>&1; then ok "az authenticated"; else warn "az not authenticated"; fi
    if command -v gcloud >/dev/null && gcloud auth list 2>/dev/null | grep -q '\*'; then ok "gcloud authenticated"; else warn "gcloud not authenticated"; fi

    phase_close "Verify"
}

next_steps() {
    phase_open "Done"
    say "${BOLD}Your workstation baseline is installed.${RESET}"
    setting "Profile" "$CHOICE_PROFILE"
    setting "Mac apps" "$(bool_label "$CHOICE_FEAT_macApps")"
    setting "Local AI" "$(bool_label "$CHOICE_FEAT_ai")"
    setting "1Password" "$(bool_label "$CHOICE_USE_OP")"
    hr
    say "${BOLD}Finish these when the prompt returns:${RESET}"
    local n=1
    if [ "$CHOICE_USE_OP" = "true" ]; then
        say "$n. ${BOLD}1Password${RESET} - sign in and enable Settings -> Developer -> SSH agent"
        n=$((n + 1))
    fi
    say "$n. ${BOLD}bootstrap auth${RESET} - gh, az, gcloud, AKS/GKE, git signing"
    dim "    bash $SOURCE_DIR/scripts/bootstrap-auth.sh"
    n=$((n + 1))
    say "$n. ${BOLD}reload shell${RESET} - start using the managed zsh config"
    dim "    exec zsh"
    n=$((n + 1))
    say "$n. ${BOLD}restart macOS${RESET} - some defaults only take full effect after reboot"
    hr
    say "${BOLD}Useful commands${RESET}"
    setting "health check" "bash $SOURCE_DIR/scripts/doctor.sh"
    setting "change setup" "bash $SOURCE_DIR/install.sh --configure-only"
    setting "upgrade later" "chezup"
    printf "%s\n" "${CYAN}│${RESET}"
    printf "%s  %sWizard complete.%s\n" "${GREEN}✓${RESET}" "$BOLD" "$RESET"
    printf "\n"
}

main() {
    require_non_root
    banner
    probe
    choices
    confirm_phase
    execute
    self_test
    next_steps
}

main "$@"
