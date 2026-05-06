# Brewfile — the COMMON tier. Always installed regardless of profile.
#
# This file is paired with `Brewfile.personal` and `Brewfile.work` — the
# brew-bundle chezmoi script picks which extras to layer on top based on the
# `profile` value you chose at `chezmoi init` time (personal / work / both).
#
# Edit a profile-specific extra by editing the matching Brewfile.<profile>.
# Move a package between tiers by cutting the line and pasting into the
# appropriate file.
#
# Regenerate the common file from a known-good machine:
#   brew bundle dump --describe --force --file=~/Dev/Personal/dotfiles/Brewfile
# (then move profile-specific lines back into Brewfile.personal / Brewfile.work)
#
# Notes on package choices:
#   - Terraform isn't in homebrew-core (HashiCorp pulled it after the BSL
#     license change in 2023). We install it from HashiCorp's official tap.
#     If license terms ever bother you, OpenTofu (`brew "opentofu"`) is a
#     Linux Foundation fork with identical HCL syntax — switch by swapping
#     the two `terraform` lines for it.
#   - google-cloud-sdk and docker-desktop are casks, not formulae.

tap "hashicorp/tap"

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

# ─── Kubernetes ───────────────────────────────────────────────────────────────
# Java/Maven/Gradle/Node/Python are managed by mise — see ~/.config/mise/config.toml
brew "kubernetes-cli"                  # kubectl
brew "kubectx"                         # also installs `kubens` — switch contexts/namespaces fast
brew "k9s"                             # kubernetes TUI
brew "stern"                           # multi-pod log tailing
brew "helm"

# ─── Azure ────────────────────────────────────────────────────────────────────
brew "azure-cli"                       # `az` CLI — sign in via `az login`
brew "Azure/kubelogin/kubelogin"       # required for kubectl against AKS clusters using Azure AD

# ─── Google Cloud ─────────────────────────────────────────────────────────────
# The full Cloud SDK (`gcloud`, `gsutil`, `bq`) comes from the gcloud-cli cask
# below. There's NO Homebrew formula for `gke-gcloud-auth-plugin` — Google
# distributes it as a gcloud SDK component. After `gcloud auth login`, run:
#     gcloud components install gke-gcloud-auth-plugin
# Required for kubectl ≥ 1.26 to authenticate against GKE clusters (the
# legacy in-tree GCP auth provider was dropped).

# ─── Infrastructure-as-Code ───────────────────────────────────────────────────
brew "hashicorp/tap/terraform"         # official Terraform from HashiCorp's tap
brew "tflint"                          # static analysis for Terraform / OpenTofu
brew "terraform-docs"                  # generate Markdown docs from Terraform modules

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
