# What you get

| Area | What's in the box |
|---|---|
| **Terminal** | [Ghostty](https://ghostty.org) with Catppuccin Frappé, JetBrainsMono Nerd Font, transparent titlebar, blurred background. Theme YAML at `~/.config/ghostty/themes/catppuccin-frappe` (chezmoi-managed, so it's deterministic across Ghostty versions). |
| **Multiplexer** | [Zellij](https://zellij.dev) with the Catppuccin Frappé theme, compact layout, mouse + clipboard integration, session persistence. Launch with the `zj` alias. Auto-attach on shell startup is opt-in (commented snippet in `.zshrc`). |
| **Prompt** | [Starship](https://starship.rs) with Catppuccin Frappé palette and Nerd Font symbols. Two-line prompt that surfaces git branch/status, language versions, Kubernetes context, and Azure/GCP account context only when relevant — keeps it clean otherwise. See [the prompt examples](#what-the-prompt-looks-like) below. |
| **Shell** | zsh with full XDG layout, direnv hook (auto-activates each project's devbox env on `cd`), fzf integration (`Ctrl-R` history search, `**<Tab>` completion), zoxide smart directory jumping, Carapace completions, `zsh-completions` + `zsh-syntax-highlighting`, Claude personal wrapper, modern CLI aliases (`ls→eza`, `cat→bat`, `find→fd`). |
| **Git** | Identity + 1Password commit signing via `op-ssh-sign`, delta diffs, useful aliases (`s`, `lg`, `wip`, `undo`, `amend`, `fixup`), pull rebase, rerere. |
| **Runtimes and project CLIs** | **Per-project** via [Devbox](https://www.jetify.com/devbox) (Nix-backed). Each project's repo carries its own `devbox.json` + `.envrc`; on `cd` direnv activates the project's pinned JDK/Kotlin/Postgres/Node/Terraform/kubectl/etc. without polluting the global PATH. Devbox itself isn't in homebrew — `.chezmoiscripts/run_onchange_before_01b-install-devbox.sh.tmpl` handles both the Jetify curl-installer for the CLI and the Determinate Nix bootstrap for the `/nix` store. Starter templates for backend, Kubernetes, Terraform, and OpenTofu projects live in [`examples/devbox/`](../examples/devbox/). Azure/GCP account CLIs stay global; the project-specific Kubernetes/IaC tools stay pinned here. |
| **Brew** | Workstation baseline + per-profile extras. Full list with one-line rationale per package in [`Brewfile`](../Brewfile). Categories: modern CLI, git productivity (`lazygit`, `pre-commit`, `direnv`), shell/editor tools, global account CLIs (`gh`, `az`, `gcloud`), Docker Desktop, Ghostty, VS Code, 1Password, fonts, and optional GUI apps. Project-specific tools such as Kubernetes CLIs, Terraform/OpenTofu, DB clients/servers, and language runtimes are intentionally Devbox-owned. |
| **Editor (GUI)** | VS Code is installed by Homebrew. User settings are managed by chezmoi, marketplace extensions come from `vscode/extensions.txt`, and the JetBrains Kotlin extension is installed from the latest upstream VSIX release. |
| **Editor (terminal)** | [Neovim](https://neovim.io) with [LazyVim](https://www.lazyvim.org) and the Catppuccin Frappé flavor. First launch auto-installs `lazy.nvim`, then LazyVim pulls in LSP (via mason), treesitter, telescope, nvim-tree, which-key, gitsigns, and the standard distribution. Backend-dev language extras (Java/Python/TypeScript/JSON/YAML/Docker/Terraform/Markdown) ship commented-out in `lua/config/lazy.lua` — uncomment whichever you want. |
| **macOS** | Fast key repeat, no autocorrect, full keyboard nav, expanded save/print panels, Finder shows everything and can quit, Dock auto-hide, screenshots → `~/Pictures/Screenshots`, TextEdit plain text by default, screensaver password immediately. Idempotent — `def_write` helper only writes when the value differs from current. |

Full source-to-destination mapping in [Mapping](mapping.md).

### What the prompt looks like

Starship modules show up only when contextually relevant, so the prompt grows with the situation. A few examples (rendered plain here; in Ghostty they're Catppuccin-tinted):

```text
# Plain directory, no git, no project — minimal noise
~/Developer ❯

# Inside a git repo on a clean branch
~/Developer/personal/dotfiles on  main ❯

# Java project on a feature branch with 2 modified + 1 untracked file
~/Developer/work/api on  feat/auth !2 ?1 via  21.0.5 ❯

# Same project, now with a Kubernetes context active because k8s/ exists
~/Developer/work/api on  feat/auth via  21.0.5 ⎈ prod (default) ❯

# After a slow command (>2s), the right-side block shows the duration
~/Developer/work/api on  main ❯ mvn test                              took 47s
```

The `❯` prompt char turns red on a non-zero exit status. Language icons require a Nerd Font (JetBrainsMono Nerd Font, installed by the Brewfile and set in Ghostty).
