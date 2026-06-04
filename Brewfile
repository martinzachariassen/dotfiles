# Brewfile — the CORE tier. Always installed regardless of profile or features.
#
# This is the smallest set that makes the dotfiles' shell experience work as
# documented: a Catppuccin-themed Ghostty + Starship + Zellij + zsh stack with
# the modern CLI replacements wired into aliases, devbox + direnv for per-project
# runtimes, chezmoi for managing this repo, and 1Password for SSH + git signing.
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
brew "coreutils"               # GNU date/tar/sort/etc. as gdate, gtar, …
brew "curl"
brew "direnv"                  # per-directory env vars + auto-activates devbox via .envrc
brew "gh"                      # GitHub CLI
brew "git"
brew "git-delta"               # syntax-highlighted git diffs
brew "jq"                      # JSON
brew "lazygit"                 # git TUI — staging, blame, branch ops, all interactive
brew "pre-commit"              # git hook framework
brew "tldr"                    # `tldr <cmd>` — concise example-driven help
brew "tree"
brew "wget"
brew "yq"                      # YAML
# devbox: NOT a brew formula. Installed via Jetify's official curl-installer
# in .chezmoiscripts/run_onchange_before_01b-install-devbox.sh.tmpl, which runs
# before this Brewfile is touched. Devbox itself manages per-project runtimes
# (Java/Kotlin/Postgres/…) via Nix; on first `devbox shell` it bootstraps Nix
# in multi-user mode if absent.

# ─── Modern CLI replacements (the shell config aliases these by default) ──────
brew "bat"                     # cat
brew "btop"                    # top
brew "carapace"                # richer shell completions for many CLIs
brew "duf"                     # df
brew "dust"                    # disk usage
brew "eza"                     # ls
brew "fd"                      # find
brew "fzf"                     # fuzzy finder; integrated into zsh (Ctrl-R)
brew "grpcurl"                 # curl, but for gRPC
brew "hadolint"                # Dockerfile linter (backs the hadolint VS Code ext)
brew "httpie"                  # curl, but human
brew "mkcert"                  # locally-trusted dev certificates
brew "ripgrep"                 # grep
brew "shellcheck"              # shell-script linter (editor ext + pre-commit + CI)
brew "shfmt"                   # shell-script formatter (backs the shell-format VS Code ext)
brew "zoxide"                  # smarter cd based on directory frecency

# ─── Runtimes ─────────────────────────────────────────────────────────────────
brew "node"                    # global Node.js/npm (per-project versions still via devbox)

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
cask "kotlin-lsp"              # JetBrains Kotlin LSP CLI for non-VS Code clients
cask "visual-studio-code"      # VS Code app; settings/extensions managed by chezmoi

# ─── JDKs (stable paths for VS Code's Java server) ────────────────────────────
# devbox/Nix JDK paths are content-hashed and churn on update/GC, which makes
# VS Code's Java language server keep losing its classpath. These Homebrew
# Temurin JDKs give the editor a stable anchor; project build versions are still
# pinned per project via Gradle toolchains. Paths:
#   /Library/Java/JavaVirtualMachines/temurin-{21,25}.jdk/Contents/Home
cask "temurin@21"              # JDK 21 (LTS) — editor + Gradle daemon default
cask "temurin@25"              # JDK 25 (LTS) — registered runtime for newer projects

# ─── Fonts ────────────────────────────────────────────────────────────────────
cask "font-fira-code-nerd-font"        # secondary; nice ligatures
cask "font-jetbrains-mono-nerd-font"   # primary; Ghostty references this

# ─── Mac App Store apps (requires `mas`) ──────────────────────────────────────
# brew "mas"
# mas "Xcode", id: 497799835
