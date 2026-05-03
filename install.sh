#!/usr/bin/env bash
# install.sh — one-liner bootstrap for a fresh Mac
#
# Usage on a brand-new machine:
#   curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
#
# Or, if you've already cloned the repo:
#   bash ~/Dev/Personal/dotfiles/install.sh

set -euo pipefail

REPO="${DOTFILES_REPO:-git@github.com:martinzachariassen/dotfiles.git}"
SOURCE_DIR="${DOTFILES_DIR:-$HOME/Dev/Personal/dotfiles}"

# ─── 1. Xcode Command Line Tools ──────────────────────────────────────────────
if ! xcode-select -p >/dev/null 2>&1; then
    echo "==> Installing Xcode Command Line Tools (a GUI dialog will appear)…"
    xcode-select --install
    echo "==> When the install completes, re-run this script."
    exit 1
fi

# ─── 2. Homebrew ──────────────────────────────────────────────────────────────
if ! command -v brew >/dev/null 2>&1; then
    echo "==> Installing Homebrew…"
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

# ─── 3. chezmoi ───────────────────────────────────────────────────────────────
if ! command -v chezmoi >/dev/null 2>&1; then
    echo "==> Installing chezmoi…"
    brew install chezmoi
fi

# ─── 4. Clone repo to ~/Dev/Personal/dotfiles ────────────────────────────────
if [ ! -d "$SOURCE_DIR/.git" ]; then
    echo "==> Cloning $REPO into $SOURCE_DIR"
    mkdir -p "$(dirname "$SOURCE_DIR")"
    git clone "$REPO" "$SOURCE_DIR"
fi

# ─── 5. Initialize chezmoi from the cloned source ────────────────────────────
# .chezmoi.toml.tmpl writes ~/.config/chezmoi/chezmoi.toml with the sourceDir
# baked in, so future `chezmoi diff/apply/edit/...` find the repo without --source.
# (This also prompts for name/email/signingKey on first run — answers persist.)
mkdir -p "$HOME/.config/chezmoi"
echo "==> Running chezmoi init from $SOURCE_DIR"
chezmoi init --source="$SOURCE_DIR"

# ─── 6. Apply dotfiles ───────────────────────────────────────────────────────
# This runs every chezmoi script in order:
#   - run_once_before_01-install-homebrew (no-op if brew already there)
#   - all dotfiles get written
#   - run_onchange_after_02-brew-bundle      → brew bundle install
#   - run_onchange_after_03-vscode-extensions → code --install-extension ×N
#   - run_once_after_04-macos-defaults        → macos-defaults.sh (sudo prompt, ONCE per machine)
echo "==> Running chezmoi apply"
chezmoi apply

# ─── 7. Re-init so the [diff] pager block picks up delta now that brew bundle ─
# has installed it. The .chezmoi.toml.tmpl gates that block on `lookPath delta`,
# which only succeeds after step 6 has finished. Idempotent — answers persist.
echo "==> Re-running chezmoi init to wire up delta as the diff pager"
chezmoi init --source="$SOURCE_DIR"

# ─── 8. Tighten permissions on Homebrew share dirs ───────────────────────────
# Apple Silicon Homebrew sometimes leaves /opt/homebrew/share/zsh* directories
# group-writable, which makes zsh's compinit prompt at every shell startup.
# Strip those bits once here so first-shell experience is silent. (The brew
# bundle chezmoi script repeats this after every future bundle.)
echo "==> Tightening /opt/homebrew/share permissions (compinit safety)"
chmod -R go-w /opt/homebrew/share 2>/dev/null || true

# ─── 9. Self-test ─────────────────────────────────────────────────────────────
# Quick sanity check that the bootstrap actually delivered the things you'd
# expect. Failures here are non-fatal — they just print a warning so you
# notice. (e.g. brew bundle skipped a package, a cask failed to symlink, etc.)
echo
echo "==> Verifying bootstrap"
verify() {
    local name="$1" cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        printf "    \033[32m✓\033[0m  %s\n" "$name"
    else
        printf "    \033[31m✗\033[0m  %s   (\`%s\` failed)\n" "$name" "$cmd"
    fi
}
verify "git"             "git --version"
verify "chezmoi"         "chezmoi --version"
verify "mise"            "mise --version"
verify "starship"        "starship --version"
verify "zellij"          "zellij --version"
verify "kubectl"         "kubectl version --client=true"
verify "lazygit"         "lazygit --version"
verify "direnv"          "direnv version"
verify "claude (CLI)"    "command -v claude"
verify "Ghostty.app"     "test -d /Applications/Ghostty.app"
verify "VS Code.app"     "test -d '/Applications/Visual Studio Code.app'"
verify "1Password.app"   "test -d /Applications/1Password.app"

echo
echo "All done. Next steps:"
echo "  1. Sign in to 1Password           (so SSH agent + git signing work)"
echo "  2. gh auth login                  (GitHub)"
echo "  3. gcloud auth login              (optional)"
echo "  4. Install your work Claude       (see WORK-SETUP.md)"
echo "  5. exec zsh                       (reload shell with new config)"
echo "  6. Restart your Mac               (some macOS defaults need a full reboot)"
