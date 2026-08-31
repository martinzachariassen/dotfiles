# Documentation

Deeper guides for this dotfiles repo. The [root README](../README.md) is the
landing page; these are the detail behind it.

**Looking for one feature?** Its own README is the single home for its prose —
what it does, how to use it, and why it works the way it does. These pages cover
what spans features, plus a tour of the configured environment.

| | | | |
|---|---|---|---|
| [auth](../features/auth/README.md) | [brew](../features/brew/README.md) | [claude](../features/claude/README.md) | [clean](../features/clean/README.md) |
| [containers](../features/containers/README.md) | [converge](../features/converge/README.md) | [distill](../features/distill/README.md) | [doctor](../features/doctor/README.md) |
| [locale](../features/locale/README.md) | [macos](../features/macos/README.md) | [runtimes](../features/runtimes/README.md) | [setup](../features/setup/README.md) |
| [sign](../features/sign/README.md) | [storecode](../features/storecode/README.md) | [vscode](../features/vscode/README.md) | [xcode](../features/xcode/README.md) |

## Setup & workflow

| Doc | Covers |
|---|---|
| [install.md](install.md) | Bootstrapping a Mac — the three scenarios, `install.sh` flags, cleaning up drift, migrating off the old direnv stack. |
| [commands.md](commands.md) | The `chez <verb>` surface: the generated table of every verb, how `chez up` works phase by phase, and the output conventions every verb shares. |
| [packages.md](packages.md) | Package tiers (core + profile + module Brewfiles), profiles, the optional-module catalog, and the plain-text setup wizard. |

## Internals

| Doc | Covers |
|---|---|
| [architecture.md](architecture.md) | The `src/` vs. root-tooling split, the feature/core division, and the registry that ties the command surface, the help and the health check together. |
| [lifecycle.md](lifecycle.md) | What `chezmoi apply` does stage by stage — the hook ordering, the convergence guarantee, and where each piece lives. |
| [macos.md](macos.md) | Every macOS system setting applied — keyboard, Finder, Dock, screenshots, security, Touch ID for sudo. |
| [development.md](development.md) | Quality gates, the CI matrix, the bats suites, and how to run every check locally. |
| [distill.md](distill.md) | The nightly distiller: how `chezdistill` turns past Claude sessions into the `MAIN.md` every future session loads — setup, the two destinations, the rubric that decides what gets captured, backup and restore, cost, and troubleshooting. |

## The configured environment

| Doc | Covers |
|---|---|
| [shell.md](shell.md) | zsh (XDG layout), modern CLI replacements, fzf/zoxide/carapace, mise runtimes, and git. |
| [terminal.md](terminal.md) | Ghostty, Zellij, Starship, and the Catppuccin Mocha theme. |
| [editors.md](editors.md) | VS Code (managed settings + extensions) and Neovim (LazyVim). |
| [ai.md](ai.md) | The Claude apps and the shared Claude/Copilot defaults. |
