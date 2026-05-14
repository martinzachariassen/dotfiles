# Brewfile — the CORE tier. Always installed regardless of profile or features.
#
# This is the smallest set that makes the dotfiles' shell experience work as
# documented: a Catppuccin-themed Ghostty + Starship + Zellij + zsh stack with
# the modern CLI replacements wired into aliases, devbox + direnv for per-project
# runtimes, chezmoi for managing this repo, and 1Password for SSH + git signing.
#
# Optional add-ons live in brewfiles/Brewfile.<feature> files and are layered on
# top of this one based on your answers to the install wizard. See:
#   brewfiles/Brewfile.mac-apps   — Rectangle, Raycast, Stats, Chrome, dive (mac-only QoL)
#   brewfiles/Brewfile.personal   — personal-only casks (you fill in)
#   brewfiles/Brewfile.work       — work-only casks, including Claude Code CLI
#
# Regenerate from a known-good machine:
#   brew bundle dump --describe --force --file=~/Dev/Personal/dotfiles/Brewfile
# (then move feature-specific lines back into the matching brewfiles/Brewfile.<feature>)

# ─── Core CLI ─────────────────────────────────────────────────────────────────
brew "git"
brew "git-delta"               # syntax-highlighted git diffs
brew "gh"                      # GitHub CLI
brew "azure-cli"               # global Azure account/subscription CLI; project kubectl stays in Devbox
cask "gcloud-cli"              # global Google Cloud account/project CLI; project kubectl stays in Devbox
brew "lazygit"                 # git TUI — staging, blame, branch ops, all interactive
brew "pre-commit"              # git hook framework
# devbox: NOT a brew formula. Installed via Jetify's official curl-installer
# in .chezmoiscripts/run_onchange_before_01b-install-devbox.sh.tmpl, which runs
# before this Brewfile is touched. Devbox itself manages per-project runtimes
# (Java/Kotlin/Postgres/…) via Nix; on first `devbox shell` it bootstraps Nix
# in multi-user mode if absent.
brew "chezmoi"                 # this very repo's manager
brew "direnv"                  # per-directory env vars + auto-activates devbox via .envrc
brew "wget"
brew "curl"
brew "jq"                      # JSON
brew "yq"                      # YAML
brew "tree"
brew "tldr"                    # `tldr <cmd>` — concise example-driven help
brew "coreutils"               # GNU date/tar/sort/etc. as gdate, gtar, …

# ─── Modern CLI replacements (the shell config aliases these by default) ──────
brew "eza"                     # ls
brew "bat"                     # cat
brew "ripgrep"                 # grep
brew "fd"                      # find
brew "fzf"                     # fuzzy finder; integrated into zsh (Ctrl-R)
brew "dust"                    # disk usage
brew "duf"                     # df
brew "btop"                    # top
brew "httpie"                  # curl, but human
brew "mkcert"                  # locally-trusted dev certificates
brew "grpcurl"                 # curl, but for gRPC

# ─── Editor (terminal) ────────────────────────────────────────────────────────
brew "neovim"                  # init.lua in dot_config/nvim ships LazyVim presets

# ─── Shell ────────────────────────────────────────────────────────────────────
brew "zsh-completions"
brew "zsh-syntax-highlighting"
brew "zsh-autosuggestions"     # fish-style type-ahead suggestions (→ to accept)
brew "starship"                # cross-shell prompt
brew "zellij"                  # terminal multiplexer (modern tmux alternative)

# ─── GUI essentials (terminal + 1Password are foundational here) ──────────────
cask "ghostty"                 # terminal emulator (Catppuccin Frappé)
cask "visual-studio-code"      # VS Code app; settings/extensions sync via VS Code cloud
cask "1password"               # GUI app — SSH agent + git signing live here
cask "1password-cli"           # `op` CLI — used by chezmoi if you template secrets
cask "docker-desktop"          # if you'd rather use colima/podman, swap this line

# ─── Fonts ────────────────────────────────────────────────────────────────────
cask "font-jetbrains-mono-nerd-font"   # primary; Ghostty reference this
cask "font-fira-code-nerd-font"        # secondary; nice ligatures

# ─── Mac App Store apps (requires `mas`) ──────────────────────────────────────
# brew "mas"
# mas "Xcode", id: 497799835
