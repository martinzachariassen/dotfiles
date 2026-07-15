# Documentation

Deeper guides for this dotfiles repo, split by topic. The [root README](../README.md)
is the overview and quick start; these docs are the detail behind it.

## Setup & workflow

| Doc | Covers |
|---|---|
| [install.md](install.md) | Bootstrapping a Mac — the three scenarios, `install.sh` flags, the deprecation cleanup, migrating off the old direnv stack. |
| [commands.md](commands.md) | The everyday verbs (`chezup`, `chezdoctor`) and the full set of occasional helpers (`chezreset`, `chezreinit`, `chezmirror`, …). |
| [packages.md](packages.md) | Package tiers (core + profile + module Brewfiles), profiles, the optional-module catalog, and the plain-text setup wizard. |

## Internals

| Doc | Covers |
|---|---|
| [architecture.md](architecture.md) | The `src/` vs. root-tooling split, repository layout, and how `scripts/` is organized. |
| [lifecycle.md](lifecycle.md) | What `chezmoi apply` does stage by stage — the hook ordering, the convergence guarantee, and where each piece lives. |
| [macos.md](macos.md) | Every macOS system setting applied — keyboard, Finder, Dock, screenshots, security, Touch ID for sudo. |
| [development.md](development.md) | Quality gates, the CI matrix, the bats suites, and how to run every check locally. |

## The configured environment

| Doc | Covers |
|---|---|
| [shell.md](shell.md) | zsh (XDG layout), modern CLI replacements, fzf/zoxide/carapace, mise runtimes, and git. |
| [terminal.md](terminal.md) | Ghostty, Zellij, Starship, and the Catppuccin Frappé theme. |
| [editors.md](editors.md) | VS Code (managed settings + extensions) and Neovim (LazyVim). |
| [ai.md](ai.md) | Local + hosted AI: Ollama, the Claude apps, and the shared Claude/Copilot persona. |
| [nightly-distill.md](nightly-distill.md) | The 01:00 conversation distiller — memory, digests, weekly rollups, and how it follows you between machines. |
