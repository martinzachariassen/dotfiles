#!/usr/bin/env bash
#
# Phase 0 bootstrap. Runs before the repo exists, so: plain echo, no library.
#
#   curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash

set -euo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/martinzachariassen/dotfiles.git}"
REPO_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"

# An INPUT, like lib/brew.sh's DOT_BREW_BIN: without one, step 2's "not
# installed yet" branch is unreachable on every machine anyone could test from.
# Its own name and its own default; install.sh still shares nothing.
BREW_PREFIX="${DOTFILES_BREW_PREFIX:-/opt/homebrew}"

echo "==> dotfiles bootstrap"
echo "    repo: $REPO_URL"
echo "    into: $REPO_DIR"
echo "    plan: 1 Xcode tools  2 Homebrew  3 bash 5  4 clone  5 dot apply"
echo

TOTAL_STEPS=5
step() {
  printf '==> [%s/%s] %s\n' "$1" "$TOTAL_STEPS" "$2"
}

# --- Guards -----------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || {
  echo "This is macOS only." >&2
  exit 1
}
[ "$(id -u)" -ne 0 ] || {
  echo "Do not run this as root." >&2
  exit 1
}
[ "$(uname -m)" = "arm64" ] || {
  echo "This is Apple Silicon only; this Mac reports $(uname -m)." >&2
  exit 1
}

# Below the bottle floor every formula compiles from source: hours, often
# failing outright. A warning, not a refusal -- the machine is the user's call.
# Not a guard: a version this cannot read says nothing, and says it silently.
MACOS_FLOOR=14
if macos=$(sw_vers -productVersion 2>/dev/null); then
  case "${macos%%.*}" in
    '' | *[!0-9]*) ;;
    *)
      if [ "${macos%%.*}" -lt "$MACOS_FLOOR" ]; then
        echo "Warning: macOS $macos is older than $MACOS_FLOOR." >&2
        echo "  Homebrew has no prebuilt bottles for it, so every package compiles" >&2
        echo "  from source. Expect hours, and expect some of it to fail." >&2
        echo "  Ctrl-C now to stop; continuing in 10 seconds." >&2
        sleep 10
      fi
      ;;
  esac
fi

# --- 1. Xcode Command Line Tools --------------------------------------------
# The GUI installer is asynchronous: trigger it, then poll.
if xcode-select -p >/dev/null 2>&1; then
  step 1 "Xcode Command Line Tools already installed"
else
  step 1 "Installing Xcode Command Line Tools (click Install in the dialog)"
  xcode-select --install >/dev/null 2>&1 || true

  attempts=0
  max_attempts=180 # 180 * 10s = 30 minutes
  until xcode-select -p >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$max_attempts" ]; then
      echo
      echo "Timed out waiting for Command Line Tools." >&2
      echo "Finish the dialog, then re-run this script." >&2
      exit 1
    fi
    printf '.'
    sleep 10
  done
  echo
fi

# --- 2. Homebrew ------------------------------------------------------------
if [ -x "$BREW_PREFIX/bin/brew" ]; then
  step 2 "Homebrew already installed"
  eval "$("$BREW_PREFIX/bin/brew" shellenv)"
else
  step 2 "Installing Homebrew (it will ask for your password)"

  # sudo's credential expires after five minutes; a cold install on a slow
  # connection takes longer, so keep it refreshed until it stops working.
  sudo -v
  while sudo -n true 2>/dev/null; do sleep 50; done &
  keepalive=$!
  trap 'kill "$keepalive" 2>/dev/null || true' EXIT

  # /bin/bash: Homebrew's installer supports the system shell. Bash 5 comes next.
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Before the `exec` below, which runs no EXIT trap.
  kill "$keepalive" 2>/dev/null || true
  trap - EXIT

  eval "$("$BREW_PREFIX/bin/brew" shellenv)"
fi
echo "    Homebrew at $(brew --prefix)"

# --- 3. bash 5 ---------------------------------------------------------------
# One of five places that must agree on bash 5 (core/Brewfile, bin/dot,
# uninstall.sh, lib/dot.sh). Here because step 5 needs it before core/Brewfile
# runs; tests/contract.bats holds the five together.
if brew list --versions bash >/dev/null 2>&1; then
  step 3 "bash 5 already installed"
else
  step 3 "Installing bash 5 (macOS ships 3.2, from 2007)"
  # HOMEBREW_NO_ASK: from Homebrew 6, `brew install` asks before pulling in a
  # dependency, and under `curl | bash` there is no stdin left to answer with.
  # `brew bundle` sets this itself, so only this bare call needs it.
  HOMEBREW_NO_ASK=1 brew install bash
fi

# --- 4. The repo ------------------------------------------------------------
if [ -d "$REPO_DIR/.git" ]; then
  step 4 "Updating existing checkout"

  # Neither branch is fatal to the install: the checkout on disk is already
  # usable, so say so rather than passing git's error through.
  if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
    echo "$REPO_DIR has uncommitted changes, so it cannot be updated." >&2
    echo "  See them:      git -C $REPO_DIR status" >&2
    echo "  Then re-run this, or install from what you have:" >&2
    echo "    $REPO_DIR/bin/dot apply" >&2
    exit 1
  fi
  if ! git -C "$REPO_DIR" pull --ff-only; then
    echo "Could not fast-forward $REPO_DIR -- it has local commits, or the" >&2
    echo "branch has diverged from the remote." >&2
    echo "  Inspect:       git -C $REPO_DIR log --oneline --graph -20" >&2
    echo "  Or install from what you have:" >&2
    echo "    $REPO_DIR/bin/dot apply" >&2
    exit 1
  fi
elif [ -e "$REPO_DIR" ]; then
  echo "$REPO_DIR exists and is not a git checkout. Move it aside first." >&2
  exit 1
else
  step 4 "Cloning"
  mkdir -p "$(dirname "$REPO_DIR")"
  # Full history, not --depth=1: both profiles enable dotfiles-dev, so this is
  # a checkout you edit and commit from.
  git clone "$REPO_URL" "$REPO_DIR"
fi

# --- 5. Hand off ------------------------------------------------------------
step 5 "Handing off to dot apply"
echo "    It installs the core packages, asks what you want on this machine,"
echo "    then links your files. It writes a log and tells you where."
echo

# Under `curl | bash` stdin is the pipe, so the wizard is handed the terminal.
if [ ! -r /dev/tty ]; then
  echo "No terminal available, so the setup wizard cannot ask anything." >&2
  echo "Run this instead, from a terminal:" >&2
  echo "  $REPO_DIR/bin/dot apply" >&2
  exit 1
fi

exec bash "$REPO_DIR/bin/dot" apply </dev/tty
