<div align="center">

# dotfiles

[![CI](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Managed by chezmoi](https://img.shields.io/badge/managed%20by-chezmoi-66ccff)](https://chezmoi.io)
[![Shell](https://img.shields.io/badge/shell-bash%20%2B%20zsh-4EAA25?logo=gnubash&logoColor=white)](#daily-commands)
[![Catppuccin Frappé](https://img.shields.io/badge/Catppuccin-Frapp%C3%A9-f2d5cf?labelColor=303446)](https://github.com/catppuccin/catppuccin)
[![Conventional Commits](https://img.shields.io/badge/commits-conventional-fe5196?logo=conventionalcommits&logoColor=white)](https://www.conventionalcommits.org)
[![Last commit](https://img.shields.io/github/last-commit/martinzachariassen/dotfiles?logo=github)](https://github.com/martinzachariassen/dotfiles/commits/main)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**One command turns a fresh Mac into a backend workstation.**

Personal macOS setup managed by [chezmoi](https://chezmoi.io) — terminal, shell, editors,
Homebrew apps, [mise](https://mise.jdx.dev)-managed runtimes, and macOS defaults, all wired up.

<!-- Hero screenshot slot: drop a terminal shot at assets/hero.png and uncomment.
<img src="assets/hero.png" alt="Ghostty + Zellij + Starship on Catppuccin Frappé" width="800">
-->

</div>

---

## Contents

- [Highlights](#highlights)
- [What you get](#what-you-get)
- [Quick start](#quick-start)
  - [Brand-new Mac](#brand-new-mac)
  - [Existing Mac with an older setup](#existing-mac-with-an-older-setup)
  - [Already set up — staying current](#already-set-up--staying-current)
- [Daily commands](#daily-commands)
- [How it works](#how-it-works)
- [Repository layout](#repository-layout)
- [Documentation](#documentation)
- [Development](#development)
- [License](#license)

---

## Highlights

<table>
  <tr>
    <td width="33%" valign="top">
      <h3>🧙 One-command bootstrap</h3>
      A single <a href="install.sh"><code>curl | bash</code></a> takes a fresh (or legacy)
      Mac from zero to a fully configured workstation — Xcode CLT, Homebrew, this repo,
      every package, and macOS defaults.
    </td>
    <td width="33%" valign="top">
      <h3>🔁 Idempotent &amp; convergent</h3>
      <code>chezmoi apply</code> reconciles <em>real installed state</em> on every run.
      "Make this Mac match the repo" always works — re-run anytime, no separate fix step.
    </td>
    <td width="33%" valign="top">
      <h3>🙅 No <code>sudo</code> lifestyle</h3>
      Everything runs as your normal user. Homebrew and the macOS steps ask for your
      password themselves, only when they actually need it.
    </td>
  </tr>
  <tr>
    <td width="33%" valign="top">
      <h3>🎯 Two everyday verbs</h3>
      <a href="install.sh"><code>install.sh</code></a> bootstraps a fresh Mac;
      <a href="scripts/bin/chezup.sh"><code>chezup</code></a> converges an existing one
      (pull → preview → apply).
    </td>
    <td width="33%" valign="top">
      <h3>🧩 Layered packages</h3>
      A core <a href="packages/Brewfile">Brewfile</a> plus composable
      <a href="packages/">profile + module layers</a> (mac-apps, personal, work),
      chosen in the setup wizard and mapped in <code>src/.chezmoidata/packages.toml</code>.
    </td>
    <td width="33%" valign="top">
      <h3>✅ CI-guarded</h3>
      Every push lints shell, renders the full template matrix, runs
      <a href="tests/">bats suites</a>, and enforces Conventional Commits.
    </td>
  </tr>
</table>

> Targets **macOS on Apple Silicon**. Everything runs as your normal user — **never with `sudo`**.

## What you get

| Area | Baseline |
|---|---|
| 🖥 **Terminal** | Ghostty, Zellij, Starship, Catppuccin Frappé, JetBrainsMono Nerd Font. |
| 🐚 **Shell** | zsh with XDG layout, fzf, zoxide, Carapace completions, syntax highlighting, modern CLI aliases. |
| ✏️ **Editors** | VS Code via Homebrew (extensions in [`packages/vscode-extensions.txt`](packages/vscode-extensions.txt)), Neovim with LazyVim. |
| 🔀 **Git** | 1Password SSH signing, delta diffs, useful aliases, pull rebase, rerere. |
| 📦 **Runtimes** | mise for per-project Java/Node/Python; global defaults in `~/.config/mise/config.toml`. |
| 🤖 **Local AI** | Default `macApps` module: Ollama (brew service) plus the Claude and Claude Code apps. |
| 🧰 **Workstation apps** | Homebrew-managed core apps, optional Mac app extras, profile-specific personal/work layers. |
| 🍎 **macOS** | Keyboard, Finder, Dock, screenshots, TextEdit, and security defaults. |

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
bash ~/Developer/personal/dotfiles/scripts/bin/bootstrap-auth.sh  # finishes git signing
exec zsh                                                       # reload the managed shell
chezdoctor                                                     # verify everything is healthy
sudo shutdown -r now                                           # reboot to finish macOS defaults
```

### Existing Mac with an older setup

Use the **same installer** — it snapshots any pre-existing legacy dotfiles into a timestamped backup before taking over (skip with `SKIP_BACKUP=1`), then converges the machine:

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

It also runs the **[deprecation cleanup](docs/install.md#deprecation-cleanup)** so you don't carry forward tools the repo no longer manages (old `node`/`temurin` casks, devbox, direnv, the `/nix` store). Afterwards, reload and sanity-check:

```sh
exec zsh
chezdoctor      # warns about any leftover devbox/Nix/direnv it couldn't remove
```

> **Coming from the devbox/direnv setup?** Runtimes are now managed by mise — see [docs/shell.md](docs/shell.md#runtimes-mise) and the [migration note](docs/install.md#coming-from-the-devboxdirenv-setup).

### Already set up — staying current

```sh
chezup       # pull latest repo changes, preview, then apply
```

Only changing profile, identity, modules, or signing (no full bootstrap) — the
plain-text [wizard](docs/packages.md#the-wizard) re-asks the questions, then
applies for you:

```sh
bash ~/Developer/personal/dotfiles/scripts/bin/wizard.sh
```

> The wizard replaces chezmoi's own TUI picker, which is unreliable under
> `curl | bash`. It asks with plain prompts (three tiers that degrade to fit the
> terminal), then feeds chezmoi the answers as flags. To set the Mac up **as
> new**, use `chezreset`. Full detail — the prompt tiers and the install flags
> (`DOTFILES_REPO`, `DOTFILES_DIR`, `--promptDefaults`) — is in
> [docs/install.md](docs/install.md#advanced-flags) and
> [docs/packages.md](docs/packages.md#the-wizard).

## Daily commands

The whole everyday surface is **two verbs plus a health check**. Both verbs end in the same `chezmoi apply`, which reconciles *real installed state* on every run — so it always installs what the Brewfile declares. It never *uninstalls*, though: `chez` only flags packages you have but the Brewfile doesn't, and `chezmirror` reconciles that removal direction on demand.

| Command | What it does |
|---|---|
| `chezup` | **Converge this Mac to the repo:** pull the latest changes, preview the drift, then apply. The everyday command. |
| `install.sh` | **Bootstrap a new Mac** from scratch (the same apply path under the hood). |
| `chezdoctor` | Read-only **health check** for repo, chezmoi, brew, auth, signing, mise, and shell layout. |

Change your setup — profile, optional modules, or signing — by re-running the
plain-text wizard, which overrides your saved answers:

```sh
chezreset               # re-ask profile / modules / signing, then apply
```

> `chezreinit` is a different tool: it runs plain `chezmoi init`, which — via
> chezmoi's `prompt*Once` functions — keeps every answer you've already given
> and only asks for setup keys still blank. So it fills in newly-added questions
> but never lets you re-choose existing ones; reach for `chezreset` for that.

There's also a set of occasional helpers — `chez`, `chezreinit`, `chezbump`,
`chezaudit`, `chezmirror`, `dotfiles` — documented in
**[docs/commands.md](docs/commands.md#advanced--occasional-helpers)**.

## How it works

`chezup` runs in three phases: **update repo** (`git pull --ff-only`), **review
pending changes** (`chezmoi status` — stops here if nothing drifted), then
**apply** (one confirm gate, then `chezmoi apply --force`). It honours `DRY_RUN=1`
and `YES=1`, and passes trailing args through to `chezmoi apply`.

`install.sh` is a tiny bootstrap fetched via `curl | bash` **before the repo
exists on disk**: it installs only the prerequisites (Xcode CLT → Homebrew →
chezmoi → clone), then hands off to the plain-text wizard, which feeds your
answers to `chezmoi init --apply`.

What `apply` does after that — the hook ordering, the convergence guarantee, and
where each piece lives — is in **[docs/lifecycle.md](docs/lifecycle.md)**.

## Repository layout

The repo root splits cleanly into **what chezmoi deploys** (everything under
`src/`, its source directory — see [`.chezmoiroot`](.chezmoiroot)) and **the
tooling that supports it** (everything else at the root, never deployed to
`$HOME`):

```
src/          # ← chezmoi's source dir; everything here deploys to $HOME
packages/     # core Brewfile + profile/module layers + editor lists
scripts/      # tooling grouped by who runs it: bin/ (verbs), ci/ (checks), lib/ (helpers)
install.sh    # tiny bootstrap; hands off to `chezmoi init --apply`
tests/        # bats suites
docs/         # these guides
```

The full layout, chezmoi naming conventions, and the `{{ .chezmoi.workingTree }}`
path idiom are in **[docs/architecture.md](docs/architecture.md)**.

## Documentation

Deeper guides live in [`docs/`](docs/) ([index](docs/README.md)):

| Doc | Covers |
|---|---|
| [install.md](docs/install.md) | Bootstrap scenarios, `install.sh` flags, deprecation cleanup. |
| [commands.md](docs/commands.md) | Every verb — `chezup`, `chezdoctor`, and the occasional helpers. |
| [packages.md](docs/packages.md) | Package tiers, profiles, the module catalog, and the wizard. |
| [architecture.md](docs/architecture.md) | The `src/` split, repo layout, and `scripts/` organization. |
| [lifecycle.md](docs/lifecycle.md) | What `chezmoi apply` does, stage by stage. |
| [development.md](docs/development.md) | Quality gates, the CI matrix, and the bats suites. |
| [shell.md](docs/shell.md) · [terminal.md](docs/terminal.md) · [editors.md](docs/editors.md) · [ai.md](docs/ai.md) | The configured environment — zsh/CLI/mise/git, Ghostty/Zellij/Starship, VS Code/Neovim, and AI tooling. |

## Development

```sh
shellcheck install.sh scripts/bin/*.sh scripts/ci/*.sh scripts/lib/*.sh   # lint shell
bats tests/                                                               # unit tests
pre-commit run --all-files                                               # the full local gate set
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs shellcheck, renders every chezmoi template across the profile/modules matrix, runs the bats suites, lints config, checks spelling, resolves Homebrew names on macOS, and enforces Conventional Commit PR titles. Full detail in **[docs/development.md](docs/development.md)**.

## License

MIT. See [LICENSE](LICENSE).
