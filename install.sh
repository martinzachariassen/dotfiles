#!/usr/bin/env bash
# install.sh — bootstraps a fresh macOS (Apple Silicon) machine, then hands off to
# `chezmoi init --apply`. Idempotent; safe to re-run.
# Env: DOTFILES_REPO=<url>, DOTFILES_DIR=<path>, QUIET=1 (results only).
# Extra args skip the wizard and forward to chezmoi init.

set -euo pipefail

REPO="${DOTFILES_REPO:-https://github.com/martinzachariassen/dotfiles.git}"
SOURCE_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"

# ── UI ────────────────────────────────────────────────────────────────────────
# Deliberately duplicated from core/ui.sh: this file runs via
# `curl | bash` before the repo exists on disk, so there is nothing to source.
# Keep the vocabulary identical so the handoff to the wizard is seamless.
if [ -t 1 ]; then
    BOLD=$'\033[1m' DIM=$'\033[2m' GREEN=$'\033[32m' YELLOW=$'\033[33m'
    BLUE=$'\033[34m' RED=$'\033[31m' CYAN=$'\033[36m' RESET=$'\033[0m'
else
    BOLD="" DIM="" GREEN="" YELLOW="" BLUE="" RED="" CYAN="" RESET=""
fi
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8* | *utf8* | *UTF8*)
        BAR="│" NODE="◆" OK_MARK="✓" ARROW_MARK="→" FAIL_MARK="✗"
        BAR_FULL="█" BAR_EMPTY="░"
        BOX_TOP="╭────────────────────────────────────────────────────────────╮"
        BOX_BOTTOM="╰────────────────────────────────────────────────────────────╯"
        ;;
    *)
        BAR="|" NODE="*" OK_MARK="OK" ARROW_MARK=">" FAIL_MARK="X"
        BAR_FULL="#" BAR_EMPTY="-"
        BOX_TOP="+------------------------------------------------------------+"
        BOX_BOTTOM="+------------------------------------------------------------+"
        ;;
esac

rail() { printf '%s%s%s' "$CYAN" "$BAR" "$RESET"; }
say() { printf '%s  %s\n' "$(rail)" "$1"; }
ok() { printf '%s  %s%s%s %s\n' "$(rail)" "$GREEN" "$OK_MARK" "$RESET" "$1"; }
info() { printf '%s  %s%s%s %s\n' "$(rail)" "$BLUE" "$ARROW_MARK" "$RESET" "$1"; }
warn() { printf '%s  %s!%s %s\n' "$(rail)" "$YELLOW" "$RESET" "$1" >&2; }
dim() { printf '%s  %s%s%s\n' "$(rail)" "$DIM" "$1" "$RESET"; }
die() {
    printf '%s  %s%s%s %s\n' "$(rail)" "$RED" "$FAIL_MARK" "$RESET" "$1" >&2
    exit 1
}
explain() {
    [ "${QUIET:-0}" = "1" ] && return 0
    local line
    for line in "$@"; do
        if [ -z "$line" ]; then printf '%s\n' "$(rail)"; else dim "$line"; fi
    done
    return 0
}

STEP_TOTAL=5
STEP_INDEX=0
STEP_T0=0
now() { date +%s 2>/dev/null || echo 0; }
elapsed() {
    local delta=$(($(now) - STEP_T0))
    [ "$STEP_T0" -gt 0 ] && [ "$delta" -ge 3 ] || return 0
    if [ "$delta" -lt 60 ]; then printf '%ds' "$delta"; else printf '%dm%02ds' "$((delta / 60))" "$((delta % 60))"; fi
}
# bar DONE TOTAL — built by appending; bash substring arithmetic is byte-based
# and would slice a multi-byte block glyph in half.
bar() {
    local done="$1" total="$2" width=16 filled i out=""
    filled=$((done * width / total))
    i=0
    while [ "$i" -lt "$filled" ]; do
        out="$out$BAR_FULL"
        i=$((i + 1))
    done
    while [ "$i" -lt "$width" ]; do
        out="$out$BAR_EMPTY"
        i=$((i + 1))
    done
    printf '%s' "$out"
}
step() {
    STEP_INDEX=$((STEP_INDEX + 1))
    STEP_T0="$(now)"
    echo
    printf '%s%s%s  %s%s%s %s[%d/%d]%s %s%s%s\n' \
        "$CYAN" "$NODE" "$RESET" "$DIM" "$(bar "$((STEP_INDEX - 1))" "$STEP_TOTAL")" "$RESET" \
        "$DIM" "$STEP_INDEX" "$STEP_TOTAL" "$RESET" "$BOLD" "$1" "$RESET"
}
step_ok() {
    local t
    t="$(elapsed)"
    if [ -n "$t" ]; then
        printf '%s  %s%s%s %s %s(%s)%s\n' "$(rail)" "$GREEN" "$OK_MARK" "$RESET" "$1" "$DIM" "$t" "$RESET"
    else
        ok "$1"
    fi
}

# The wizard/chezmoi exec later replaces this handler with its own.
on_interrupt() {
    printf '\033[?25h\n' >/dev/tty 2>/dev/null || true
    warn "aborted — nothing further was applied."
    exit 130
}
trap on_interrupt INT TERM

# Put brew on PATH whether just installed or present but not yet exported.
load_brew() {
    command -v brew >/dev/null 2>&1 && return 0
    local candidate
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$candidate" ]; then
            eval "$("$candidate" shellenv)"
            return 0
        fi
    done
    return 1
}

# --- 0. Guards ------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "this installer only supports macOS."
[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not with sudo."
[ "$(uname -m)" = "arm64" ] || warn "this repo targets Apple Silicon; continuing on $(uname -m)."

# --- Overview -------------------------------------------------------------
# Say upfront what this will do, how long it takes, and what it will ask for —
# the install is mostly silent downloads, and an unexplained wait reads as a hang.
echo
printf '%s%s%s\n' "$CYAN" "$BOX_TOP" "$RESET"
printf '%s%s%s  %sSetting up this Mac%s%*s%s%s%s\n' \
    "$CYAN" "$BAR" "$RESET" "$BOLD" "$RESET" 39 "" "$CYAN" "$BAR" "$RESET"
printf '%s%s%s\n' "$CYAN" "$BOX_BOTTOM" "$RESET"
explain \
    "" \
    "This installs your tools and config from scratch. It is safe to re-run:" \
    "every step checks first and skips what is already done." \
    "" \
    "Roughly 15-25 minutes, almost all of it downloading." \
    "You will be asked for: your macOS password (for Homebrew now, and again" \
    "later for app installs and macOS settings), then a few setup questions." \
    "" \
    "  1. Xcode Command Line Tools   Apple's compilers — Homebrew needs them" \
    "  2. Homebrew                   the package manager everything else uses" \
    "  3. chezmoi                    renders this repo into your home folder" \
    "  4. Clone the dotfiles repo    into $SOURCE_DIR" \
    "  5. Setup wizard, then apply   asks your preferences, then installs"

# --- 1. Xcode Command Line Tools -----------------------------------------
step "Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
    step_ok "already installed"
else
    explain "Apple ships these separately and only via a GUI installer."
    info "opening Apple's installer — accept the dialog when it appears"
    xcode-select --install 2>/dev/null || true
    # Bounded wait (~30 min) for the GUI installer. Tick visibly: a silent poll
    # for half an hour is indistinguishable from a hung script.
    waited=0
    while [ "$waited" -lt 1800 ]; do
        xcode-select -p >/dev/null 2>&1 && break
        sleep 5
        waited=$((waited + 5))
        # Reassure every 30s, on one rewritten line so it doesn't flood.
        if [ $((waited % 30)) -eq 0 ] && [ -t 1 ]; then
            printf '\r%s  %swaiting for Apple'"'"'s installer… %dm%02ds%s' \
                "$(rail)" "$DIM" "$((waited / 60))" "$((waited % 60))" "$RESET"
        fi
    done
    [ -t 1 ] && printf '\r\033[K'
    xcode-select -p >/dev/null 2>&1 || die "Xcode CLT still missing — re-run once Apple's installer finishes."
    step_ok "installed"
fi

# --- 2. Homebrew ----------------------------------------------------------
# Inlined rather than shared with scripts/lib/homebrew.sh: this runs before the
# repo is cloned (step 4 below), so there's nothing local to source yet.
step "Homebrew"
if load_brew; then
    step_ok "already installed — $(command -v brew)"
else
    explain \
        "Homebrew installs every CLI and app this setup uses." \
        "It needs administrator access to create /opt/homebrew."
    if [ -r /dev/tty ]; then
        # Say what is about to happen before sudo takes the line. sudo writes its
        # prompt to /dev/tty at column 0, outside this script's rail, so without
        # a lead-in it reads as an unexplained password box in the middle of an
        # install — and nothing on screen says the typing is invisible.
        #
        # `info`, not `explain`: QUIET=1 drops prose, and a password prompt is
        # the one thing that must never arrive unannounced.
        info "macOS will ask for your login password — nothing appears as you type"
        explain "If you have Touch ID for sudo enabled, just tap the sensor instead."
        # %u so it names the account, matching what macOS shows elsewhere.
        sudo -v -p "    macOS password for %u: " || die "could not obtain admin access for Homebrew."
        ok "admin access granted"
    fi
    info "installing Homebrew — this is the long step, 5-10 min"
    # Homebrew's installer echoes every privileged command it runs. Twenty lines
    # of raw "/usr/bin/sudo /bin/mkdir -p …" immediately after a password prompt
    # look like something went wrong; they are simply what it always prints.
    explain \
        "Homebrew now prints each command it runs as administrator." \
        "A wall of \`/usr/bin/sudo …\` lines here is normal, not an error."
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    load_brew || die "Homebrew installed but 'brew' is not on PATH."
    step_ok "installed"
fi

# --- 3. chezmoi -----------------------------------------------------------
step "chezmoi"
if command -v chezmoi >/dev/null 2>&1; then
    step_ok "already installed — $(chezmoi --version | head -n1 | cut -d, -f1)"
else
    explain "chezmoi turns this repo into the real files in your home folder."
    info "installing chezmoi via Homebrew"
    brew install chezmoi
    step_ok "installed — $(chezmoi --version | head -n1 | cut -d, -f1)"
fi

# --- 4. Clone the repo (idempotent) --------------------------------------
step "Dotfiles repo"
if [ -d "$SOURCE_DIR/.git" ]; then
    step_ok "already cloned — $SOURCE_DIR"
else
    # A non-empty, non-git directory here would make `git clone` die with a raw
    # error under `set -e`. Say what's wrong instead.
    if [ -d "$SOURCE_DIR" ] && [ -n "$(ls -A "$SOURCE_DIR" 2>/dev/null)" ]; then
        die "$SOURCE_DIR exists but is not a git checkout — move it aside, or set DOTFILES_DIR."
    fi
    explain "Your config lives here from now on; edit it, then run \`chezup\`."
    info "cloning into $SOURCE_DIR"
    mkdir -p "$(dirname "$SOURCE_DIR")"
    git clone "$REPO" "$SOURCE_DIR"
    step_ok "cloned"
fi

# --- 5. Hand off to the setup wizard -------------------------------------
# Wizard reads /dev/tty directly, so it works under `curl | bash` (chezmoi's raw-mode
# TUI doesn't). Extra args skip it and go straight to chezmoi.
step "Setup wizard"
if [ "$#" -eq 0 ]; then
    explain \
        "A few questions about how you want this Mac set up." \
        "Every answer is changeable later with \`chezsetup\`."
    exec bash "$SOURCE_DIR/scripts/bin/wizard.sh"
fi
info "extra args given — skipping the wizard, handing off to chezmoi init"
exec chezmoi init --apply --force --source="$SOURCE_DIR" "$@"
