#!/usr/bin/env bash
# sandbox.sh — build a throwaway chezmoi setup for the chezup demo recording.
#
# Creates a self-contained source repo + target HOME with a little fake drift so
# `chezup` has something realistic to show, WITHOUT touching the real machine or
# reflecting any personal config into the GIF. Driven by chezup.tape.
#
# Requires HOME and DOTFILES_DIR to be set to disposable /tmp paths.

set -euo pipefail

: "${HOME:?set HOME to a /tmp sandbox path}"
: "${DOTFILES_DIR:?set DOTFILES_DIR to a /tmp sandbox path}"

# Safety: only ever operate under /tmp so a stray run can't nuke a real HOME.
case "$HOME" in /tmp/*) ;; *) echo "sandbox.sh: refusing, HOME is not under /tmp" >&2; exit 1 ;; esac

rm -rf "$HOME"
mkdir -p "$DOTFILES_DIR" "$HOME/.config/chezmoi"

cd "$DOTFILES_DIR"
git init -q
git config user.name  "Demo User"
git config user.email "demo@example.com"

# A managed file that already exists in the target...
printf '# managed by dotfiles\nexport EDITOR=nvim\n' > dot_zshrc
git add -A
git -c commit.gpgsign=false commit -qm "init"

cat > "$HOME/.config/chezmoi/chezmoi.toml" <<EOF
sourceDir = "$DOTFILES_DIR"
[data]
  profile = "personal"
EOF

# Apply once so dot_zshrc lands in the target, then introduce drift:
chezmoi apply --force >/dev/null 2>&1 || true

# ...edit the source so it now differs from the target  -> shows as "M .zshrc"
printf '# managed by dotfiles\nexport EDITOR=nvim\nexport PAGER=delta\n' > dot_zshrc
# ...and add a brand-new managed file not yet in the target -> shows as "A .gitconfig"
printf '[init]\n  defaultBranch = main\n' > dot_gitconfig
