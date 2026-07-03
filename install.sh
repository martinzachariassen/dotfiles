#!/usr/bin/env bash
# install.sh — one-shot bootstrap for a fresh macOS (Apple Silicon) machine.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
#
# It installs only the prerequisites that must exist before chezmoi can take
# over — Xcode Command Line Tools, Homebrew, chezmoi, and this repo — then hands
# off to `chezmoi init --apply`, which runs the setup wizard (the prompts in
# .chezmoi.toml.tmpl) and applies everything else. Every step is a no-op once
# satisfied, so the script is safe to re-run.
#
# Environment:
#   DOTFILES_REPO=<url>   upstream repo   (default: this repo)
#   DOTFILES_DIR=<path>   local source    (default: ~/Developer/personal/dotfiles)
#
# Any extra arguments are forwarded to `chezmoi init`, e.g.:
#   ... | bash -s -- --promptDefaults   # non-interactive: accept all defaults
#   ... | bash -s -- --prompt           # re-ask every setup question

set -euo pipefail

REPO="${DOTFILES_REPO:-https://github.com/martinzachariassen/dotfiles.git}"
SOURCE_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() {
    printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
    exit 1
}

# Put brew on PATH whether it was just installed or is already present but not yet
# exported in this non-login shell.
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
    # Wait (bounded, ~30 min) for the GUI installer to finish.
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
    info "Cloning $REPO into $SOURCE_DIR…"
    mkdir -p "$(dirname "$SOURCE_DIR")"
    git clone "$REPO" "$SOURCE_DIR"
fi

# --- 5. Hand off to chezmoi ----------------------------------------------
# chezmoi runs the setup wizard on the terminal — it opens /dev/tty for prompts,
# so `curl | bash` works — then applies. With no terminal at all (CI/containers)
# accept defaults so it can't hang. Extra script args pass straight through.
init_args=(init --apply --source="$SOURCE_DIR")
if [ "$#" -eq 0 ] && [ ! -t 0 ] && [ ! -r /dev/tty ]; then
    warn "no terminal detected — accepting default answers (--promptDefaults)."
    init_args+=(--promptDefaults)
fi
info "Handing off to chezmoi: setup wizard, then apply."
exec chezmoi "${init_args[@]}" "$@"
