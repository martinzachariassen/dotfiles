#!/usr/bin/env bash
# install.sh — bootstrap a fresh macOS (Apple Silicon) machine, then hand off to
# `chezmoi init --apply`. Idempotent; safe to re-run.
#
# Env: DOTFILES_REPO=<url>, DOTFILES_DIR=<path>. Extra args forward to chezmoi
# init, e.g. `... | bash -s -- --promptDefaults`.

set -euo pipefail

REPO="${DOTFILES_REPO:-https://github.com/martinzachariassen/dotfiles.git}"
SOURCE_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() {
    printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
    exit 1
}

# Clean Ctrl-C during the prerequisite steps; the wizard/chezmoi exec replaces
# this handler with its own.
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

# --- 1. Xcode Command Line Tools -----------------------------------------
if ! xcode-select -p >/dev/null 2>&1; then
    info "Installing Xcode Command Line Tools — accept Apple's dialog when it opens."
    xcode-select --install 2>/dev/null || true
    # Bounded wait (~30 min) for the GUI installer.
    for _ in $(seq 1 360); do
        xcode-select -p >/dev/null 2>&1 && break
        sleep 5
    done
    xcode-select -p >/dev/null 2>&1 || die "Xcode CLT still missing — re-run once Apple's installer finishes."
fi
info "Xcode Command Line Tools present."

# --- 2. Homebrew ----------------------------------------------------------
if ! load_brew; then
    info "Installing Homebrew. It needs administrator access on a fresh Mac."
    if [ -r /dev/tty ]; then
        sudo -v -p "Enter your macOS password (for Homebrew): " || die "could not obtain admin access for Homebrew."
    fi
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    load_brew || die "Homebrew installed but 'brew' is not on PATH."
fi
info "Homebrew at $(command -v brew)."

# --- 3. chezmoi -----------------------------------------------------------
if ! command -v chezmoi >/dev/null 2>&1; then
    info "Installing chezmoi…"
    brew install chezmoi
fi
info "Using $(chezmoi --version | head -n 1)."

# --- 4. Clone the repo (idempotent) --------------------------------------
if [ -d "$SOURCE_DIR/.git" ]; then
    info "Repo already present at $SOURCE_DIR."
else
    # Brace-delimit ${SOURCE_DIR}: system bash 3.2 otherwise absorbs the trailing
    # multibyte "…" into the var name and dies under `set -u`.
    info "Cloning $REPO into ${SOURCE_DIR}…"
    mkdir -p "$(dirname "$SOURCE_DIR")"
    git clone "$REPO" "$SOURCE_DIR"
fi

# --- 5. Hand off to the setup wizard -------------------------------------
# The plain-text wizard reads /dev/tty directly, so it works under `curl | bash`
# where chezmoi's raw-mode promptChoice TUI is unreliable. Callers passing their
# own chezmoi flags skip the wizard and go straight to chezmoi.
if [ "$#" -eq 0 ]; then
    info "Starting the setup wizard, then applying."
    exec bash "$SOURCE_DIR/scripts/bin/wizard.sh"
fi
info "Extra args given — handing off directly to chezmoi init."
exec chezmoi init --apply --source="$SOURCE_DIR" "$@"
