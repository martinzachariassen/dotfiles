# Brewfile — the CORE tier. Always installed regardless of profile or features.
#
# This is the smallest set that makes the dotfiles' shell experience work as
# documented: a Catppuccin-themed Ghostty + Starship + Zellij + zsh stack with
# the modern CLI replacements wired into aliases, mise for language runtimes,
# chezmoi for managing this repo, and 1Password for SSH + git signing.
#
# Optional add-ons live in brewfiles/Brewfile.<feature> files and are layered on
# top of this one based on your answers to the install wizard. See:
#   brewfiles/Brewfile.mac-apps   — GUI apps (productivity, media, dev) + AI tooling
#   brewfiles/Brewfile.personal   — personal-only casks (you fill in)
#   brewfiles/Brewfile.work       — work-only casks (cloud CLIs + work apps)
#
# Entries are sorted alphabetically within each section. Regenerate from a
# known-good machine:
#   brew bundle dump --describe --force --file=~/Developer/personal/dotfiles/Brewfile
# (then move feature-specific lines back into the matching brewfiles/Brewfile.<feature>)

# ─── Core CLI ─────────────────────────────────────────────────────────────────
brew "chezmoi"                 # this very repo's manager
brew "gh"                      # GitHub CLI
brew "git"
brew "git-delta"               # syntax-highlighted git diffs
brew "jq"                      # JSON
brew "lazygit"                 # git TUI — staging, blame, branch ops, all interactive
brew "pre-commit"              # git hook framework
brew "tlrc"                    # `tldr <cmd>` — maintained Rust client (old `tldr` formula was disabled upstream)
brew "typos-cli"               # source-code spell checker (pre-commit hook; CI uses the action)

# ─── Modern CLI replacements (the shell config aliases these by default) ──────
brew "bat"                     # cat
brew "carapace"                # richer shell completions for many CLIs
brew "eza"                     # ls
brew "fd"                      # find
brew "fzf"                     # fuzzy finder; integrated into zsh (Ctrl-R)
brew "hadolint"                # Dockerfile linter (backs the hadolint VS Code ext)
brew "ripgrep"                 # grep
brew "shellcheck"              # shell-script linter (editor ext + pre-commit + CI)
brew "shfmt"                   # shell-script formatter (backs the shell-format VS Code ext)
brew "zoxide"                  # smarter cd based on directory frecency

# ─── Runtimes ─────────────────────────────────────────────────────────────────
# mise owns language runtimes (java, node, python, …). Global defaults live in
# ~/.config/mise/config.toml (managed: dot_config/mise/config.toml); per-project
# versions + env vars live in each project's own mise.toml. mise installs to
# stable paths (~/.local/share/mise/installs/<tool>/<version>), so VS Code's
# Java server gets a non-churning JDK path — see settings.json.tmpl.
brew "mise"                    # polyglot runtime manager (replaces node + temurin casks)

# ─── Editor (terminal) ────────────────────────────────────────────────────────
brew "neovim"                  # init.lua in dot_config/nvim ships LazyVim presets

# ─── Shell ────────────────────────────────────────────────────────────────────
brew "starship"                # cross-shell prompt
brew "zellij"                  # terminal multiplexer (modern tmux alternative)
brew "zsh-autosuggestions"     # fish-style type-ahead suggestions (→ to accept)
brew "zsh-completions"
brew "zsh-syntax-highlighting" # source this last in zshrc

# ─── GUI essentials (terminal + 1Password are foundational here) ──────────────
cask "1password"               # GUI app — SSH agent + git signing live here
cask "1password-cli"           # `op` CLI — used by chezmoi if you template secrets
cask "docker-desktop"          # if you'd rather use colima/podman, swap this line
cask "ghostty"                 # terminal emulator (Catppuccin Frappé)
cask "visual-studio-code"      # VS Code app; settings/extensions managed by chezmoi

# JDKs are managed by mise (java = ["temurin-21", "temurin-25"] in the global
# config), not Homebrew. mise install paths are stable, so VS Code's Java server
# anchors to them directly — see dot_config/mise/config.toml + settings.json.tmpl.

# ─── Fonts ────────────────────────────────────────────────────────────────────
cask "font-jetbrains-mono-nerd-font"   # primary; Ghostty + VS Code reference this

# ─── Mac App Store apps (requires `mas`) ──────────────────────────────────────
# brew "mas"
# mas "Xcode", id: 497799835
