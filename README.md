# dotfiles

[![CI](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Managed by chezmoi](https://img.shields.io/badge/managed%20by-chezmoi-66ccff)](https://chezmoi.io)
[![Catppuccin Frappe](https://img.shields.io/badge/Catppuccin-Frapp%C3%A9-f2d5cf?labelColor=303446)](https://github.com/catppuccin/catppuccin)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Personal macOS setup, managed by [chezmoi](https://chezmoi.io). One command turns a fresh Mac into a backend workstation with terminal, shell, editors, Git signing, Homebrew apps, Devbox project environments, and macOS defaults wired up.

## Start here

Fresh Mac or existing machine:

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

Already bootstrapped and only changing profile, identity, or feature toggles:

```sh
bash ~/Dev/Personal/dotfiles/install.sh --configure-only
```

After the wizard finishes:

```sh
open -a 1Password                              # skip if you disabled 1Password
bash ~/Dev/Personal/dotfiles/scripts/bootstrap-auth.sh # gh, az, gcloud, signing checks
exec zsh
sudo shutdown -r now
```

<details>
<summary>Advanced install flags</summary>

```sh
DRY_RUN=1       bash install.sh   # print state-changing commands without running them
YES=1           bash install.sh   # accept recommended defaults
SKIP_BACKUP=1   bash install.sh   # do not snapshot pre-existing legacy dotfiles
DOTFILES_REPO=<repo-url> bash install.sh   # point at a fork
DOTFILES_DIR=<path>      bash install.sh   # clone somewhere else
```

Guarded Homebrew cleanup modes:

```sh
bash install.sh --mirror-brew  # remove packages not in the active Brewfiles
bash install.sh --reset-brew   # uninstall everything first, then reinstall
```

</details>

## Daily commands

| Command | Use |
|---|---|
| `dotfiles` | Jump to the source repo. With arguments, manage profile/features. |
| `chez` | Preview and apply dotfile changes with one confirmation. |
| `chezup` | Pull latest repo changes, then run `chez`. |
| `chezreinit` | Pull, re-render chezmoi config, then apply. Use after wizard/data-model changes. |
| `chezdiff` | Preview dotfile drift, brew drift, and scripts that would re-run. |
| `chezdoctor` | Read-only health check for repo, chezmoi, brew, auth, signing, Devbox, and shell layout. |

Common profile and feature changes:

```sh
dotfiles profile set personal
dotfiles profile set work
dotfiles profile set both
dotfiles features list
dotfiles features enable macApps
dotfiles features disable macApps
```

## What you get

| Area | Baseline |
|---|---|
| Terminal | Ghostty, Zellij, Starship, Catppuccin Frappe, JetBrainsMono Nerd Font. |
| Shell | zsh with XDG layout, fzf, direnv, completions, syntax highlighting, and modern CLI aliases. |
| Git | 1Password SSH signing, delta diffs, useful aliases, pull rebase, rerere. |
| Project tools | Devbox + direnv for per-project JDK/Kotlin/Postgres/Node/Terraform/Kubernetes tools. |
| Editors | VS Code via Homebrew, Neovim with LazyVim for terminal work. |
| Workstation apps | Homebrew-managed core apps, optional mac app extras, and profile-specific personal/work layers. |
| macOS | Keyboard, Finder, Dock, screenshots, TextEdit, and security defaults. |

See [What you get](docs/what-you-get.md) for the full table and prompt examples.

## Documentation

| Page | Use it for |
|---|---|
| [Bootstrap](docs/bootstrap.md) | Wizard flow, profiles, features, secrets, signing, and macOS privacy permissions. |
| [Day-to-day](docs/day-to-day.md) | Chezmoi mental model, adding tools, previewing changes, aliases, and `doctor.sh`. |
| [Upgrading](docs/upgrading.md) | `chezup`, `chezreinit`, invalidation rules, and long-absence maintenance. |
| [Troubleshooting](docs/troubleshooting.md) | Known failure modes and recovery commands. |
| [Architecture](docs/architecture.md) | Chezmoi file classes, remove markers, ignored files, and apply scripts. |
| [AI tools](docs/ai-tools.md) | Claude Code personal config and Codex global instructions. |
| [Forking](docs/forking.md) | What to change when basing your own setup on this repo. |
| [Uninstall / reset](docs/uninstall-reset.md) | Homebrew mirror/reset and manual rollback notes. |
| [Reference](docs/reference.md) | Links to the important repo files. |

Other useful references:

- [Mapping](docs/mapping.md) maps every managed source file to its target in `$HOME`.
- [examples/](examples/) contains Devbox, direnv, and pre-commit starter files.

## License

MIT. See [LICENSE](LICENSE).
