#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${DOTFILES_REPO:-https://github.com/martinzachariassen/dotfiles.git}"
REPO_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"

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

if xcode-select -p >/dev/null 2>&1; then
  step 1 "Xcode Command Line Tools already installed"
else
  step 1 "Installing Xcode Command Line Tools (click Install in the dialog)"
  xcode-select --install >/dev/null 2>&1 || true

  attempts=0
  max_attempts=180
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

if [ -x "$BREW_PREFIX/bin/brew" ]; then
  step 2 "Homebrew already installed"
  eval "$("$BREW_PREFIX/bin/brew" shellenv)"
else
  step 2 "Installing Homebrew (it will ask for your password)"

  sudo -v
  while sudo -n true 2>/dev/null; do sleep 50; done &
  keepalive=$!
  trap 'kill "$keepalive" 2>/dev/null || true' EXIT

  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Before the `exec` below, which runs no EXIT trap.
  kill "$keepalive" 2>/dev/null || true
  trap - EXIT

  eval "$("$BREW_PREFIX/bin/brew" shellenv)"
fi
echo "    Homebrew at $(brew --prefix)"

if brew list --versions bash >/dev/null 2>&1; then
  step 3 "bash 5 already installed"
else
  step 3 "Installing bash 5 (macOS ships 3.2, from 2007)"
  # Homebrew 6 asks before pulling in a dependency, and under `curl | bash` there
  # is no stdin left to answer with.
  HOMEBREW_NO_ASK=1 brew install bash
fi

if [ -d "$REPO_DIR/.git" ]; then
  step 4 "Updating existing checkout"

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
  git clone "$REPO_URL" "$REPO_DIR"
fi

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
