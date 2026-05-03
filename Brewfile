# Brewfile — installed via `brew bundle --file=~/Dev/Personal/dotfiles/Brewfile`
# Regenerate from a known-good machine: `brew bundle dump --describe --force --file=~/Dev/Personal/dotfiles/Brewfile`
#
# Notes on package choices:
#   - terraform was removed from homebrew-core after the BSL license change.
#     We use opentofu (drop-in compatible). To switch back to official Terraform,
#     replace the opentofu line with:
#         tap "hashicorp/tap"
#         brew "hashicorp/tap/terraform"
#   - google-cloud-sdk and docker-desktop are casks (binary distributions),
#     not formulae.

# ─── Core CLI ─────────────────────────────────────────────────────────────────
brew "git"
brew "git-delta"               # syntax-highlighted git diffs
brew "gh"                       # GitHub CLI
brew "lazygit"                  # git TUI — staging, blame, branch ops, all interactive
brew "pre-commit"               # git hook framework (most modern Python/JS repos use it)
brew "mise"                     # runtime version manager
brew "chezmoi"                  # this very repo's manager
brew "direnv"                   # per-directory env vars; essential for multi-project work
brew "wget"
brew "curl"
brew "jq"                       # JSON
brew "yq"                       # YAML
brew "tree"
brew "tldr"                     # `tldr <cmd>` — concise example-driven help (replaces googling man pages)
brew "coreutils"                # GNU date/tar/sort/etc., available with `g` prefix (gdate, gtar)

# ─── Modern CLI replacements (used everywhere: terminal, IDE terminals, SSH) ──
brew "eza"                      # ls
brew "bat"                      # cat
brew "ripgrep"                  # grep
brew "fd"                       # find
brew "fzf"                      # fuzzy finder; integrated into zsh in .zshrc (Ctrl-R)
brew "dust"                     # disk usage
brew "duf"                      # df
brew "btop"                     # top
brew "httpie"                   # curl, but human
brew "grpcurl"                  # like curl, but for gRPC services
brew "mkcert"                   # locally-trusted dev certificates for HTTPS work

# ─── Backend / cloud / IaC ────────────────────────────────────────────────────
# Java/Maven/Gradle/Node/Python are managed by mise — see ~/.config/mise/config.toml
brew "kubernetes-cli"           # kubectl
brew "kubectx"                  # also installs `kubens` — switch contexts/namespaces fast
brew "k9s"                      # kubernetes TUI
brew "stern"                    # multi-pod log tailing
brew "helm"
brew "awscli"
brew "opentofu"                 # terraform-compatible (see header note)
brew "tflint"                   # works with both terraform and opentofu

# ─── Databases (CLI clients only — actual servers run via docker/cloud) ───────
brew "pgcli"                    # PostgreSQL CLI with auto-complete + syntax highlighting
brew "mysql-client"             # `mysql` CLI without the server
brew "redis"                    # `redis-cli` plus a local server you can run via `redis-server`

# ─── Container introspection ──────────────────────────────────────────────────
brew "dive"                     # explore docker image layers; spot bloat fast

# ─── Editors / shells ─────────────────────────────────────────────────────────
brew "neovim"
brew "zsh-completions"
brew "zsh-syntax-highlighting"
brew "starship"                 # cross-shell prompt
brew "zellij"                   # terminal multiplexer (modern tmux alternative)

# ─── Casks (GUI apps + binary distributions) ──────────────────────────────────
cask "ghostty"                  # terminal emulator
cask "visual-studio-code"
cask "docker-desktop"           # was "docker", renamed Aug 2024
cask "gcloud-cli"               # gcloud (was named google-cloud-sdk before 2025)
cask "1password"
cask "1password-cli"            # `op` CLI — used by chezmoi if you ever template secrets via `op read`
cask "claude"                   # Claude desktop GUI app
cask "claude-code@latest"       # Claude Code CLI (rolling channel — what the `claude` wrapper in .zshrc invokes).
                                # Switch to plain `cask "claude-code"` if you'd rather pin to the stable named release;
                                # you'd then `brew uninstall --cask claude-code@latest` first to free up /opt/homebrew/bin/claude.
cask "google-chrome"
cask "rectangle"                # window snapping
cask "raycast"                  # Spotlight replacement
cask "stats"                    # menu bar resource monitor

# ─── Fonts ────────────────────────────────────────────────────────────────────
cask "font-jetbrains-mono-nerd-font"
cask "font-fira-code-nerd-font"

# ─── Mac App Store apps (requires `mas`) ─────────────────────────────────────
# brew "mas"
# mas "Xcode", id: 497799835
