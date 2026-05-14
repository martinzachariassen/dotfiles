#!/usr/bin/env bash
# install.sh - guided installer for this dotfiles repo.
#
# The first version of this wizard used raw terminal mode for arrow-key menus.
# That looked nice, but it was too fragile: some terminals did not deliver the
# escape sequences as expected, and text fields could feel broken. This version
# keeps the visual structure, but uses plain, reliable numbered menus and normal
# line input for every answer.
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
SOURCE_DIR="${DOTFILES_DIR:-$HOME/Dev/Personal/dotfiles}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_BACKUP="${SKIP_BACKUP:-0}"
ASSUME_YES="${YES:-0}"
CONFIGURE_ONLY=0
RESET_BREW_REQUESTED=0
MIRROR_BREW_REQUESTED=0

FEATURE_KEYS=(macApps)

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

say()   { printf "%s  %s\n" "${CYAN}|${RESET}" "$1"; }
ok()    { printf "%s  %s✓%s %s\n" "${CYAN}|${RESET}" "$GREEN" "$RESET" "$1"; }
info()  { printf "%s  %s•%s %s\n" "${CYAN}|${RESET}" "$BLUE" "$RESET" "$1"; }
warn()  { printf "%s  %s!%s %s\n" "${CYAN}|${RESET}" "$YELLOW" "$RESET" "$1"; }
fail()  { printf "%s  %s✗%s %s\n" "${CYAN}|${RESET}" "$RED" "$RESET" "$1"; }
dim()   { printf "%s  %s%s%s\n" "${CYAN}|${RESET}" "$DIM" "$1" "$RESET"; }
hr()    { printf "%s\n" "${CYAN}|${RESET}"; }

phase_open() {
    local title="$1"
    printf "%s\n" "${CYAN}|${RESET}"
    printf "%s  %s%s%s\n" "${CYAN}>${RESET}" "$BOLD" "$title" "$RESET"
    printf "%s\n" "${CYAN}|${RESET}"
}

phase_close() {
    local title="$1"
    printf "%s\n" "${CYAN}|${RESET}"
    printf "%s  %s%s done%s\n" "${GREEN}=${RESET}" "$DIM" "$title" "$RESET"
}

run() {
    if [ "$DRY_RUN" = "1" ]; then
        printf "%s    %sDRY-RUN \$%s %s\n" "${CYAN}|${RESET}" "$DIM" "$RESET" "$*"
    else
        "$@"
    fi
}

have_tty() {
    ( exec </dev/tty >/dev/tty ) 2>/dev/null
}

prompt_read() {
    local __out="$1" prompt="$2" response
    printf "%s  %s" "${CYAN}|${RESET}" "$prompt" > /dev/tty
    IFS= read -r response < /dev/tty || response=""
    printf -v "$__out" '%s' "$response"
}

prompt_text() {
    local __out="$1" title="$2" default="${3:-}" hint="${4:-}" answer

    if ! have_tty || [ "$ASSUME_YES" = "1" ]; then
        printf -v "$__out" '%s' "$default"
        printf "%s  %s%s:%s %s%s%s\n" "${GREEN}=${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "${default:-<blank>}" "$RESET"
        return
    fi

    printf "%s  %s%s%s\n" "${CYAN}>${RESET}" "$BOLD" "$title" "$RESET" > /dev/tty
    [ -n "$hint" ] && printf "%s  %s%s%s\n" "${CYAN}|${RESET}" "$DIM" "$hint" "$RESET" > /dev/tty
    if [ -n "$default" ]; then
        prompt_read answer "Current: ${BOLD}$default${RESET}. Enter new value or leave blank to keep: "
        [ -z "$answer" ] && answer="$default"
    else
        prompt_read answer "Enter value, or leave blank to skip: "
    fi
    printf "%s  %s%s:%s %s%s%s\n" "${GREEN}=${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "${answer:-<blank>}" "$RESET"
    printf -v "$__out" '%s' "$answer"
}

prompt_confirm() {
    local __out="$1" title="$2" default_yes="${3:-1}" answer default_label result
    [ "$default_yes" = "1" ] && default_label="Y/n" || default_label="y/N"

    if ! have_tty || [ "$ASSUME_YES" = "1" ]; then
        [ "$default_yes" = "1" ] && result=true || result=false
        printf -v "$__out" '%s' "$result"
        printf "%s  %s%s:%s %s%s%s %s(default)%s\n" \
            "${GREEN}=${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$([ "$result" = true ] && echo yes || echo no)" "$RESET" "$DIM" "$RESET"
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
        "${GREEN}=${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$([ "$result" = true ] && echo yes || echo no)" "$RESET"
}

prompt_choice() {
    local __out="$1" title="$2" default="$3"
    shift 3
    local opts=("$@") n=$# i answer value label

    if ! have_tty || [ "$ASSUME_YES" = "1" ]; then
        printf -v "$__out" '%s' "$default"
        printf "%s  %s%s:%s %s%s%s %s(default)%s\n" \
            "${GREEN}=${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "$default" "$RESET" "$DIM" "$RESET"
        return
    fi

    printf "%s  %s%s%s\n" "${CYAN}>${RESET}" "$BOLD" "$title" "$RESET" > /dev/tty
    for ((i=0; i<n; i++)); do
        value="${opts[$i]%%|*}"
        label="${opts[$i]#*|}"
        if [ "$value" = "$default" ]; then
            printf "%s    %d. %s %s%s(current)%s\n" "${CYAN}|${RESET}" $((i + 1)) "$label" "$DIM" "$RESET" "$DIM" > /dev/tty
        else
            printf "%s    %d. %s\n" "${CYAN}|${RESET}" $((i + 1)) "$label" > /dev/tty
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
    printf "%s  %s%s:%s %s%s%s\n" "${GREEN}=${RESET}" "$BOLD" "$title" "$RESET" "$GREEN" "${!__out}" "$RESET"
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
    printf '%s\n' "$json" \
        | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
        | sed '/^$/d' \
        | tail -1
}

json_bool() {
    local json="$1" key="$2"
    printf '%s\n' "$json" \
        | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p" \
        | tail -1
}

toml_string() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    sed -n "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$file" | tail -1
}

toml_bool() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    sed -n "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*\\(true\\|false\\)[[:space:]]*$/\1/p" "$file" | tail -1
}

load_existing_answers() {
    EXISTING_NAME=""
    EXISTING_EMAIL=""
    EXISTING_SIGNINGKEY=""
    EXISTING_PROFILE="personal"
    EXISTING_USE_OP="true"
    EXISTING_FEAT_macApps="true"

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
            eval "EXISTING_FEAT_${key}=\"\${val:-true}\""
        done
    elif [ -f "$HOME/.config/chezmoi/chezmoi.toml" ]; then
        local cfg="$HOME/.config/chezmoi/chezmoi.toml"
        EXISTING_NAME="$(toml_string "$cfg" "name")"
        EXISTING_EMAIL="$(toml_string "$cfg" "email")"
        EXISTING_SIGNINGKEY="$(toml_string "$cfg" "signingKey")"
        EXISTING_PROFILE="$(toml_string "$cfg" "profile")"
        EXISTING_USE_OP="$(toml_bool "$cfg" "useOnePassword")"
        EXISTING_FEAT_macApps="$(toml_bool "$cfg" "macApps")"
    fi

    EXISTING_NAME="${EXISTING_NAME:-$(git config --global user.name 2>/dev/null || echo '')}"
    EXISTING_EMAIL="${EXISTING_EMAIL:-$(git config --global user.email 2>/dev/null || echo '')}"
    EXISTING_PROFILE="${EXISTING_PROFILE:-personal}"
    EXISTING_USE_OP="${EXISTING_USE_OP:-true}"
    EXISTING_FEAT_macApps="${EXISTING_FEAT_macApps:-true}"
}

banner() {
    printf "\n"
    printf "%s  %sDotfiles setup%s\n" "${CYAN}+${RESET}" "$BOLD" "$RESET"
    printf "%s  Reliable numbered wizard for a fresh or existing Mac.\n" "${CYAN}|${RESET}"
    printf "%s\n" "${CYAN}|${RESET}"
    if [ "$DRY_RUN" = "1" ]; then
        printf "%s  %sDRY-RUN MODE - no changes will be made.%s\n" "${CYAN}|${RESET}" "$YELLOW$BOLD" "$RESET"
    fi
    if [ "$ASSUME_YES" = "1" ]; then
        printf "%s  %sYES MODE - accepting recommended defaults. Homebrew reset/mirror remains off unless explicitly flagged.%s\n" "${CYAN}|${RESET}" "$YELLOW$BOLD" "$RESET"
    fi
    if [ "$CONFIGURE_ONLY" = "1" ]; then
        printf "%s  %sCONFIGURE-ONLY - updating chezmoi profile, identity, features, then applying.%s\n" "${CYAN}|${RESET}" "$YELLOW$BOLD" "$RESET"
    fi
    printf "%s  Phases: discovery -> choices -> confirm -> execute -> self-test -> next steps.\n" "${CYAN}|${RESET}"
    if have_tty && [ "$ASSUME_YES" != "1" ]; then
        local _
        printf "%s\n" "${CYAN}|${RESET}"
        prompt_read _ "Press Enter to begin "
    fi
}

probe() {
    phase_open "Phase A - Discovery"

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

    if xcode-select -p >/dev/null 2>&1; then ok "Xcode Command Line Tools present"; else info "Xcode CLT missing - installer will open Apple's installer"; fi
    if command -v brew >/dev/null 2>&1; then ok "Homebrew at $(command -v brew)"; else info "Homebrew missing - installer will install it"; fi
    if command -v chezmoi >/dev/null 2>&1; then ok "$(chezmoi --version 2>/dev/null | head -1)"; else info "chezmoi missing - installer will install it"; fi

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

    phase_close "Phase A"
}

choices() {
    phase_open "Phase B - Choices"
    load_existing_answers

    say "${BOLD}How to use this screen:${RESET} enter numbers for menus, type text into fields, or press Enter to keep the shown default."
    hr

    prompt_choice CHOICE_PROFILE "Profile" "$EXISTING_PROFILE" \
        "personal|personal - personal extras only" \
        "work|work - work extras only" \
        "both|both - personal and work extras"

    prompt_text CHOICE_NAME "Full name" "$EXISTING_NAME" "Written to ~/.config/git/config as git user.name."
    prompt_text CHOICE_EMAIL "Git email" "$EXISTING_EMAIL" "Written to ~/.config/git/config as git user.email. GitHub noreply addresses are fine."

    prompt_confirm CHOICE_USE_OP "Use 1Password for SSH auth and git signing?" "$([ "$EXISTING_USE_OP" = "true" ] && echo 1 || echo 0)"
    if [ "$CHOICE_USE_OP" = "true" ]; then
        prompt_text CHOICE_SIGNINGKEY "SSH signing public key" "$EXISTING_SIGNINGKEY" "Paste the public key line from 1Password, or leave blank to set it later."
    else
        CHOICE_SIGNINGKEY=""
    fi

    local current_macapps
    current_macapps="${EXISTING_FEAT_macApps:-true}"
    prompt_confirm CHOICE_FEAT_macApps "Install workstation Mac apps?" "$([ "$current_macapps" = "true" ] && echo 1 || echo 0)"

    CHOICE_RESET_BREW=false
    CHOICE_MIRROR_BREW=false
    if [ "$CONFIGURE_ONLY" != "1" ]; then
        if [ "$RESET_BREW_REQUESTED" = "1" ]; then
            CHOICE_RESET_BREW=true
            warn "Homebrew reset requested by --reset-brew"
        elif [ "$MIRROR_BREW_REQUESTED" = "1" ]; then
            CHOICE_MIRROR_BREW=true
            warn "Homebrew mirror requested by --mirror-brew"
        elif command -v brew >/dev/null 2>&1; then
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

    CHOICE_BACKUP_LEGACY=true
    CHOICE_REMOVE_OMZ=false
    if [ "$CONFIGURE_ONLY" != "1" ] && [ ${#PROBE_LEGACY_FILES[@]} -gt 0 ]; then
        prompt_confirm CHOICE_BACKUP_LEGACY "Back up legacy files and remove originals?" 1
    fi
    if [ "$CONFIGURE_ONLY" != "1" ] && [ "$PROBE_OMZ" = "1" ]; then
        prompt_confirm CHOICE_REMOVE_OMZ "Uninstall oh-my-zsh before applying dotfiles?" 1
    fi

    phase_close "Phase B"
}

confirm_phase() {
    phase_open "Phase C - Confirm"

    say "${BOLD}Profile:${RESET}      $CHOICE_PROFILE"
    say "${BOLD}Name:${RESET}         ${CHOICE_NAME:-<blank>}"
    say "${BOLD}Email:${RESET}        ${CHOICE_EMAIL:-<blank>}"
    say "${BOLD}1Password:${RESET}    $CHOICE_USE_OP"
    if [ -n "$CHOICE_SIGNINGKEY" ]; then
        say "${BOLD}Signing key:${RESET}  ${CHOICE_SIGNINGKEY:0:44}..."
    else
        say "${BOLD}Signing key:${RESET}  <none - set later>"
    fi
    say "${BOLD}Mac apps:${RESET}     $CHOICE_FEAT_macApps"
    say "${BOLD}Repo:${RESET}         $REPO"
    say "${BOLD}Source dir:${RESET}   $SOURCE_DIR"
    if [ "$CONFIGURE_ONLY" != "1" ]; then
        say "${BOLD}Legacy backup:${RESET} $CHOICE_BACKUP_LEGACY"
        say "${BOLD}Remove OMZ:${RESET}    $CHOICE_REMOVE_OMZ"
        say "${BOLD}Reset Homebrew:${RESET} $CHOICE_RESET_BREW"
        say "${BOLD}Mirror Homebrew:${RESET} $CHOICE_MIRROR_BREW"
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
        phase_close "Phase C"
        exit 0
    fi

    phase_close "Phase C"
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

install_xcode_clt() {
    info "Xcode Command Line Tools"
    if ! xcode-select -p >/dev/null 2>&1; then
        info "opening Apple's Command Line Tools installer"
        run xcode-select --install || true
        if [ "$DRY_RUN" != "1" ]; then
            printf "%s    %swaiting for CLT install to complete" "${CYAN}|${RESET}" "$DIM"
            local i
            for i in $(seq 1 240); do
                if xcode-select -p >/dev/null 2>&1; then printf "%s\n" "$RESET"; break; fi
                printf "."
                sleep 5
            done
            if ! xcode-select -p >/dev/null 2>&1; then
                printf "%s\n" "$RESET"
                fail "Xcode CLT install timed out after 20 minutes; re-run the installer after it finishes"
                exit 1
            fi
        fi
    fi
    ok "Xcode CLT at $(xcode-select -p 2>/dev/null || echo '<dry-run>')"
}

install_homebrew() {
    info "Homebrew"
    if ! command -v brew >/dev/null 2>&1; then
        info "installing Homebrew non-interactively"
        run /bin/bash -c "NONINTERACTIVE=1 \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    fi
    if [ "$DRY_RUN" != "1" ] && [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    ok "Homebrew at $(command -v brew 2>/dev/null || echo '<dry-run>')"
}

configure_chezmoi() {
    info "Configuring chezmoi with the answers from Phase B"
    run mkdir -p "$HOME/.config/chezmoi"

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
    run chezmoi init "${init_flags[@]}"
    ok "chezmoi configured"
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
        run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        run cp -p "$f" "$BACKUP_DIR/$rel"
        run rm -f "$f"
    done
    ok "legacy files backed up and removed"
}

execute() {
    phase_open "Phase D - Execute"

    if [ "$CONFIGURE_ONLY" = "1" ]; then
        if [ ! -d "$SOURCE_DIR/.git" ]; then fail "configure-only requires an existing repo at $SOURCE_DIR"; exit 1; fi
        if ! command -v chezmoi >/dev/null 2>&1; then fail "configure-only requires chezmoi on PATH"; exit 1; fi
        configure_chezmoi
        info "Applying dotfiles for updated profile/features"
        run chezmoi apply --force
        ok "chezmoi apply complete"
        phase_close "Phase D"
        return
    fi

    backup_legacy_files
    if [ "${CHOICE_REMOVE_OMZ:-false}" = "true" ] && [ -d "$HOME/.oh-my-zsh" ]; then
        info "uninstalling oh-my-zsh non-interactively"
        run bash -c 'yes | "$HOME/.oh-my-zsh/tools/uninstall.sh"' || warn "oh-my-zsh uninstaller errored; continuing"
    fi

    install_xcode_clt
    install_homebrew
    [ "$CHOICE_RESET_BREW" = "true" ] && reset_homebrew

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

    configure_chezmoi

    info "Applying dotfiles. Homebrew downloads dominate first install time."
    run chezmoi apply --force
    ok "chezmoi apply complete"
    [ "$CHOICE_MIRROR_BREW" = "true" ] && mirror_homebrew
    phase_close "Phase D"
}

self_test() {
    phase_open "Phase E - Self-test"
    if [ "$DRY_RUN" = "1" ]; then
        ok "DRY-RUN: skipping checks"
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
        if out=$(eval "$cmd" 2>&1); then ok "$name"; else fail "$name - $out"; fi
    }

    say "${DIM}core${RESET}"
    _v "git" git --version
    _v "chezmoi" chezmoi --version
    _v "devbox" devbox version
    _vf "Nix store /nix" "[ -d /nix ]"
    _vf "nix-daemon running" "launchctl list 2>/dev/null | grep -q org.nixos.nix-daemon"
    _v "starship" starship --version
    _v "zellij" zellij --version
    _v "lazygit" lazygit --version
    _v "direnv" direnv version
    _v "delta" delta --version
    _v "fzf" fzf --version

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

    say "${DIM}auth state (fix in Phase F if needed)${RESET}"
    if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then ok "gh authenticated"; else warn "gh not authenticated"; fi
    if command -v az >/dev/null && az account show >/dev/null 2>&1; then ok "az authenticated"; else warn "az not authenticated"; fi
    if command -v gcloud >/dev/null && gcloud auth list 2>/dev/null | grep -q '\*'; then ok "gcloud authenticated"; else warn "gcloud not authenticated"; fi

    phase_close "Phase E"
}

next_steps() {
    phase_open "Phase F - Next steps"
    local n=1
    if [ "$CHOICE_USE_OP" = "true" ]; then
        say "$n. ${BOLD}Sign in to 1Password${RESET} and enable Settings -> Developer -> SSH agent"
        n=$((n + 1))
    fi
    say "$n. ${BOLD}bash $SOURCE_DIR/scripts/bootstrap-auth.sh${RESET} - gh/az/gcloud sign-in and signing checks"
    n=$((n + 1))
    say "$n. ${BOLD}exec zsh${RESET} - reload shell configuration"
    n=$((n + 1))
    say "$n. ${BOLD}Restart your Mac${RESET} - some macOS defaults need a reboot"
    hr
    say "${DIM}Diagnose anytime:${RESET} ${BOLD}bash $SOURCE_DIR/scripts/doctor.sh${RESET}"
    say "${DIM}Re-run configuration only:${RESET} ${BOLD}bash $SOURCE_DIR/install.sh --configure-only${RESET}"
    printf "%s\n" "${CYAN}|${RESET}"
    printf "%s  %sWizard complete.%s\n" "${GREEN}+${RESET}" "$BOLD" "$RESET"
    printf "\n"
}

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
