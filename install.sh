#!/usr/bin/env bash
# install.sh — guided bootstrap for a fresh Mac.
#
# Usage on a brand-new machine:
#   curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
#
# Or, if you've already cloned the repo:
#   bash ~/Dev/Personal/dotfiles/install.sh
#
# Re-running is safe — every step is idempotent.

set -euo pipefail

REPO="${DOTFILES_REPO:-https://github.com/martinzachariassen/dotfiles.git}"
# Note: cloned via HTTPS so a fresh Mac (with no SSH agent yet) can bootstrap
# without authentication. Future `git push` from this repo automatically
# upgrades to SSH thanks to `pushInsteadOf = https://github.com/` →
# `git@github.com:` in ~/.config/git/config (chezmoi-managed).
SOURCE_DIR="${DOTFILES_DIR:-$HOME/Dev/Personal/dotfiles}"
TOTAL_STEPS=8

# ─── Helpers ──────────────────────────────────────────────────────────────────
# Color codes — only emit if stdout is a TTY (so curl-piped output stays clean).
if [ -t 1 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'
    GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RED=$'\033[31m'
    RESET=$'\033[0m'
else
    BOLD=""; DIM=""; GREEN=""; YELLOW=""; BLUE=""; RED=""; RESET=""
fi

step() {
    local n="$1" title="$2" explanation="$3"
    echo
    echo "${BOLD}${BLUE}═══ [${n}/${TOTAL_STEPS}] ${title} ═══${RESET}"
    echo "${DIM}${explanation}${RESET}"
    echo
}
ok()    { echo "  ${GREEN}✓${RESET}  $1"; }
info()  { echo "  ${BLUE}ℹ${RESET}  $1"; }
warn()  { echo "  ${YELLOW}!${RESET}  $1"; }
fail()  { echo "  ${RED}✗${RESET}  $1"; }

# ─── Banner ───────────────────────────────────────────────────────────────────
cat <<EOF

${BOLD}Dotfiles Bootstrap${RESET}
${DIM}Personal macOS setup, managed by chezmoi.${RESET}

${BOLD}What this will do:${RESET}
  1. Install Xcode Command Line Tools (if missing)
  2. Install Homebrew
  3. Install chezmoi (the dotfiles manager)
  4. Clone this repo to ${BOLD}${SOURCE_DIR}${RESET}
  5. Configure chezmoi (prompts for ${BOLD}profile${RESET}, name, email, signing key)
  6. Apply dotfiles + brew bundle + VS Code extensions + macOS defaults
  7. Re-render config now that delta is installed (diff pager wiring)
  8. Self-test — verify everything landed on PATH

${BOLD}Estimated time:${RESET} 15–20 min (mostly Homebrew downloading).

${BOLD}You will be prompted:${RESET}
  • ${YELLOW}Xcode CLT GUI dialog${RESET}     — first run only; click Install, wait, re-run
  • ${YELLOW}Profile picker${RESET}            — personal / work / both (controls casks)
  • ${YELLOW}Identity${RESET}                  — name, git email, SSH signing public key
  • ${YELLOW}Sudo password${RESET}             — once, for macOS system defaults

Press ${BOLD}Enter${RESET} to begin, or ${BOLD}Ctrl-C${RESET} to abort.
EOF

# Wait for confirmation only if we have a real TTY (skip when piped from curl
# but no TTY is attached — i.e. truly headless).
if [ -t 0 ]; then
    read -r _
fi

# ─── 1. Xcode Command Line Tools ──────────────────────────────────────────────
step "1" "Xcode Command Line Tools" \
    "Provides git, gcc, headers — Homebrew needs these. macOS shows a GUI dialog the first time."

if ! xcode-select -p >/dev/null 2>&1; then
    warn "not installed. A GUI dialog will appear; click Install and wait."
    xcode-select --install
    fail "Re-run this script after the install completes."
    exit 1
fi
ok "Xcode CLT already installed at $(xcode-select -p)"

# ─── 2. Homebrew ──────────────────────────────────────────────────────────────
step "2" "Homebrew" \
    "Package manager for macOS. Apple Silicon path: /opt/homebrew. The official installer runs non-interactively."

if ! command -v brew >/dev/null 2>&1; then
    info "installing Homebrew (no prompts; uses NONINTERACTIVE=1)"
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
ok "Homebrew at $(command -v brew)"

# ─── 3. chezmoi ───────────────────────────────────────────────────────────────
step "3" "chezmoi" \
    "Dotfile manager — reads source files in this repo and writes their rendered form to \$HOME."

if ! command -v chezmoi >/dev/null 2>&1; then
    info "installing chezmoi via brew"
    brew install chezmoi
fi
ok "chezmoi at $(command -v chezmoi)"

# ─── 4. Clone repo ────────────────────────────────────────────────────────────
step "4" "Clone repository" \
    "Source-of-truth lives at ${SOURCE_DIR}. chezmoi reads from here on every apply."

if [ ! -d "$SOURCE_DIR/.git" ]; then
    info "cloning $REPO into $SOURCE_DIR"
    mkdir -p "$(dirname "$SOURCE_DIR")"
    git clone "$REPO" "$SOURCE_DIR"
else
    ok "already cloned"
fi

# ─── 5. chezmoi init (prompts) ────────────────────────────────────────────────
step "5" "Configure chezmoi" \
    "Renders .chezmoi.toml.tmpl → ~/.config/chezmoi/chezmoi.toml. Prompts for profile + identity (one-time; answers persist)."

mkdir -p "$HOME/.config/chezmoi"
chezmoi init --source="$SOURCE_DIR"
ok "chezmoi configured for profile: $(chezmoi data --format=json 2>/dev/null | grep -o '"profile":"[^"]*"' || echo 'unknown')"

# ─── 6. chezmoi apply ─────────────────────────────────────────────────────────
step "6" "Apply dotfiles + install packages" \
    "Writes every dotfile to \$HOME, then runs: brew bundle (~10–15 min), VS Code extensions, macOS defaults (sudo prompt)."

chezmoi apply
ok "chezmoi apply complete"

# ─── 7. Re-init for delta pager ───────────────────────────────────────────────
step "7" "Re-render chezmoi config" \
    "delta wasn't on PATH at first init, so the [diff] block in chezmoi.toml was skipped. Now that brew bundle has installed it, re-init picks it up."

chezmoi init --source="$SOURCE_DIR"
ok "delta wired into chezmoi diff"

# ─── 8. Self-test ─────────────────────────────────────────────────────────────
step "8" "Verify bootstrap" \
    "Sanity check that key tools and apps actually landed. Failures are non-fatal — just heads-ups."

# Tighten zsh-related share dirs as a safety net (the brew-bundle script does
# this too, but if a cask installed *after* that ran left bad bits, this
# catches it). Scoped to just /opt/homebrew/share/zsh* — the rest of the share
# tree has 100k+ files and recursing all of it adds a minute for no benefit.
chmod -R go-w /opt/homebrew/share/zsh* 2>/dev/null || true

verify() {
    local name="$1" cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        ok "$name"
    else
        fail "$name   ${DIM}(\`$cmd\` failed)${RESET}"
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

# ─── Done ────────────────────────────────────────────────────────────────────
cat <<EOF

${BOLD}${GREEN}All done.${RESET}

${BOLD}Next steps:${RESET}
  1. Sign in to ${BOLD}1Password${RESET}        (so the SSH agent + git signing work)
  2. ${BOLD}gh auth login${RESET}               (GitHub CLI auth)
  3. ${BOLD}gcloud auth login${RESET}           (optional; if you use GCP)
  4. Install your work Claude    (see ${BOLD}WORK-SETUP.md${RESET}; only needed for work profile)
  5. ${BOLD}exec zsh${RESET}                    (reload shell with new config)
  6. ${BOLD}Restart your Mac${RESET}            (some macOS defaults need a reboot)

${DIM}Customize anytime: \`chezmoi edit ~/.zshrc\`, then \`chezmoi apply -v\`.${RESET}
${DIM}Repo: ${SOURCE_DIR}${RESET}
EOF
