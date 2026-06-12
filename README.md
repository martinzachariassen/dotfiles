# dotfiles

[![CI](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Managed by chezmoi](https://img.shields.io/badge/managed%20by-chezmoi-66ccff)](https://chezmoi.io)
[![Shell](https://img.shields.io/badge/shell-bash%20%2B%20zsh-4EAA25?logo=gnubash&logoColor=white)](#daily-commands)
[![Catppuccin Frappé](https://img.shields.io/badge/Catppuccin-Frapp%C3%A9-f2d5cf?labelColor=303446)](https://github.com/catppuccin/catppuccin)
[![Conventional Commits](https://img.shields.io/badge/commits-conventional-fe5196?logo=conventionalcommits&logoColor=white)](https://www.conventionalcommits.org)
[![Last commit](https://img.shields.io/github/last-commit/martinzachariassen/dotfiles?logo=github)](https://github.com/martinzachariassen/dotfiles/commits/main)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Personal macOS setup, managed by [chezmoi](https://chezmoi.io). **One command turns a fresh Mac into a backend workstation** — terminal, shell, editors, Homebrew apps, [mise](https://mise.jdx.dev)-managed language runtimes, and macOS defaults, all wired up.

The whole thing is built around **two everyday verbs** that look and feel like the same product:

- [`install.sh`](install.sh) — the **wizard** that bootstraps a fresh (or legacy) Mac from scratch.
- [`chezup`](scripts/chezup.sh) — the daily verb that **converges** this Mac to the repo.

Every operation is **idempotent and convergent**: `chezmoi apply` reconciles real installed state on every run, so "make this Mac match the repo" always works — no separate fix step.

> Targets **macOS on Apple Silicon**. Everything runs as your normal user — **never with `sudo`**. Homebrew and the macOS steps ask for your password themselves when they need it.

## Demos

### Bootstrap a new Mac — the wizard

`install.sh` probes the machine, asks only for what a fresh Mac can answer (profile, name, email), shows you the plan, and applies it. Arrow-key menus when you have a real terminal; plain numbered prompts over `curl | bash` or SSH.

![The install.sh wizard running in dry-run mode](assets/demo-wizard.gif)

### Stay in sync — chezup

`chezup` is the everyday command: **pull → review → apply**, in three clearly labelled phases, ending in the same `chezmoi apply` the wizard uses.

![The chezup converge flow running in dry-run mode](assets/demo-chezup.gif)

<sub>Both clips are recorded in `DRY_RUN` mode (state-changing commands are printed, never executed). Regenerate them with [`vhs`](https://github.com/charmbracelet/vhs): `vhs assets/tapes/wizard.tape` and `vhs assets/tapes/chezup.tape`.</sub>

## Quick start

Pick the scenario that matches your machine. Every step is idempotent and safe to re-run.

### Brand-new Mac

One command bootstraps Xcode Command Line Tools, Homebrew, this repo, all packages, and macOS defaults:

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

When the wizard finishes, sign in and reload:

```sh
open -a 1Password                                              # skip if disabled
bash ~/Developer/personal/dotfiles/scripts/bootstrap-auth.sh  # finishes git signing
exec zsh                                                       # reload the managed shell
chezdoctor                                                     # verify everything is healthy
sudo shutdown -r now                                           # reboot to finish macOS defaults
```

### Existing Mac with an older setup

Use the **same installer** — it snapshots any pre-existing legacy dotfiles into a timestamped backup before taking over (skip with `SKIP_BACKUP=1`), then converges the machine:

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

It also runs the **deprecation cleanup** so you don't carry forward tools the repo no longer manages — see the details below. Afterwards, reload and sanity-check:

```sh
exec zsh
chezdoctor      # warns about any leftover devbox/Nix/direnv it couldn't remove
```

<details>
<summary>What the deprecation cleanup does</summary>

- uninstalls the Homebrew packages this repo dropped (`node`, `temurin@21`, `temurin@25`, `direnv`) — language runtimes now come from **mise**;
- removes the old out-of-band `devbox` binary and the leftover `~/.config/direnv` config; and
- asks **y/N before deleting the old `/nix` store** from the previous devbox stack (it needs sudo and can't be undone — answer `n` to keep it, remove it later with `/nix/nix-installer uninstall`).

On a fresh machine that never had the old stack, the cleanup is a silent no-op.

> **Coming from the devbox/direnv setup?** Runtimes (Java/Node/Python) are now managed by mise: global defaults live in `~/.config/mise/config.toml`, and each project pins its own versions + env vars in a committed `mise.toml` (its `[env]` block replaces `.envrc`).

</details>

### Already set up — staying current

```sh
chezup       # pull latest repo changes, preview, then apply
```

Only changing profile, identity, or feature toggles (no full bootstrap):

```sh
bash ~/Developer/personal/dotfiles/install.sh --configure-only
```

<details>
<summary>Advanced install flags</summary>

```sh
DRY_RUN=1       bash install.sh   # print state-changing commands without running them
YES=1           bash install.sh   # accept recommended defaults (non-interactive)
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

The whole everyday surface is **two verbs plus a health check**. Both verbs end in the same `chezmoi apply`, which reconciles *real installed state* on every run — so it always installs what the Brewfile declares.

| Command | What it does |
|---|---|
| `chezup` | **Converge this Mac to the repo:** pull the latest changes, preview the drift, then apply. The everyday command. |
| `install.sh` | **Bootstrap a new Mac** from scratch (the same apply path under the hood). |
| `chezdoctor` | Read-only **health check** for repo, chezmoi, brew, auth, signing, mise, and shell layout. |

<details>
<summary>Advanced / occasional commands</summary>

| Command | What it does |
|---|---|
| `dotfiles` | Jump to the source repo. With arguments, manage profile/features/signing. |
| `chez` | Apply without pulling — the building block `chezup` calls. |
| `chezreinit` | Pull, re-run `chezmoi init` to pick up new data-model keys, then apply. Use after wizard/data-model changes. |
| `chezbump` | Routine dependency upgrade (`brew update && brew upgrade` + `mise upgrade`). |
| `chezaudit` | List Homebrew packages installed locally but not tracked in any Brewfile (drift detection). |

</details>

Common profile and feature changes:

```sh
dotfiles profile set personal
dotfiles profile set work
dotfiles features list
dotfiles features enable macApps
dotfiles features disable macApps
```

### How the commands work

**`chezup` runs in three phases** (see the demo above):

1. **Update repo** — `git pull --ff-only` in the source dir; reports how many commits arrived.
2. **Review pending changes** — `chezmoi status` lists the drift between the repo and `$HOME` (`A` add, `M` modify, `D` remove). If nothing drifted, it stops here.
3. **Apply** — one confirmation gate, then `chezmoi apply --force`, timed, followed by a summary card.

It honours `DRY_RUN=1` (print, don't run) and `YES=1` (skip the confirm gate), and passes any trailing arguments through to `chezmoi apply` (e.g. `chezup -v`).

**`install.sh` is the wizard** — a self-contained bootstrap script (it has to run via `curl | bash` before the repo exists on disk). It walks five phases: *check this Mac → choose setup → review plan → execute → self-test*, then prints next steps. The everyday `chezup` deliberately mirrors its banner, phases, and prompts so the two feel like one tool ("one engine, one look").

## What you get

| Area | Baseline |
|---|---|
| **Terminal** | Ghostty, Zellij, Starship, Catppuccin Frappé, JetBrainsMono Nerd Font. |
| **Shell** | zsh with XDG layout, fzf, zoxide, Carapace completions, syntax highlighting, modern CLI aliases. |
| **Editors** | VS Code via Homebrew (extensions in [`vscode/extensions.txt`](vscode/extensions.txt)), Neovim with LazyVim. |
| **Git** | 1Password SSH signing, delta diffs, useful aliases, pull rebase, rerere. |
| **Runtimes** | mise for per-project Java/Node/Python; global defaults in `~/.config/mise/config.toml`. |
| **Local AI** | Part of the default `macApps` module: Ollama (brew service) plus the Claude and Claude Code apps. |
| **Workstation apps** | Homebrew-managed core apps, optional Mac app extras, and profile-specific personal/work layers. |
| **macOS** | Keyboard, Finder, Dock, screenshots, TextEdit, and security defaults. |

## Repository layout

```
install.sh              # the bootstrap wizard (self-contained)
Brewfile                # core Homebrew packages (always installed)
brewfiles/              # profile + feature layers (mac-apps, personal, work)
.chezmoi.toml.tmpl      # chezmoi config + first-run prompts
.chezmoiscripts/        # ordered run scripts (brew bundle, mise, vscode, macOS defaults…)
dot_config/             # → ~/.config (zsh, git, mise, nvim, ghostty, starship, claude…)
scripts/                # chezup.sh, doctor.sh, dotfiles-config.sh, bootstrap-auth.sh, lib/ui.sh…
tests/                  # bats suites + drive-wizard.py (drives install.sh under a pty)
assets/                 # README demo GIFs + their vhs tapes
```

The shell verbs (`chezup`, `chezdoctor`, `dotfiles`, …) are defined in [`dot_config/zsh/dot_zshrc.tmpl`](dot_config/zsh/dot_zshrc.tmpl) and delegate to the scripts in [`scripts/`](scripts).

## Development

```sh
# Lint + parse shell
shellcheck install.sh scripts/*.sh scripts/lib/*.sh

# Run the bats test suites
bats tests/

# Drive the real wizard under a pseudo-terminal (DRY_RUN, always aborts safely)
python3 tests/drive-wizard.py        # or: python3 tests/drive-wizard.py stray

# Regenerate the README demo GIFs (needs: brew install vhs)
vhs assets/tapes/wizard.tape
vhs assets/tapes/chezup.tape
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs shellcheck, renders every chezmoi template across the profile/feature matrix, runs the bats suites, lints config, checks spelling, resolves Homebrew names on macOS, and enforces Conventional Commit PR titles.

## License

MIT. See [LICENSE](LICENSE).
</content>
