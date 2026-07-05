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
      <a href="scripts/chezup.sh"><code>chezup</code></a> converges an existing one
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

It also runs the **deprecation cleanup** so you don't carry forward tools the repo no longer manages. Afterwards, reload and sanity-check:

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

Only changing profile, identity, modules, or signing (no full bootstrap) — the
plain-text wizard re-asks the questions, then applies for you:

```sh
bash ~/Developer/personal/dotfiles/scripts/wizard.sh
```

> The wizard exists because chezmoi's own `chezmoi init --prompt` renders an
> interactive TUI picker that is unreliable under `curl | bash` and some
> terminals (it can fail to register navigation and just confirm the default).
> The wizard asks with plain prompts, then feeds chezmoi the answers as flags.
> When `gum` is installed and you're on a real terminal (i.e. any re-run after
> the first install), the choice/module prompts upgrade to arrow-key + space-
> toggle pickers with your current selection pre-checked; otherwise the plain
> numbered menus are used. Force plain with `WIZARD_NO_GUM=1`.
> To set the Mac up **as new** (replay first-time setup too), use `chezreset`.

<details>
<summary>Advanced install flags</summary>

With no extra arguments `install.sh` runs the plain-text wizard
(`scripts/wizard.sh`), which asks the setup questions and applies. Passing any
extra arguments **bypasses the wizard** and forwards them straight to
`chezmoi init --apply` (for scripted/CI use). It also reads two env vars:

```sh
DOTFILES_REPO=<repo-url> bash install.sh          # point at a fork
DOTFILES_DIR=<path>      bash install.sh          # clone somewhere else
curl -fsSL …/install.sh | bash -s -- --promptDefaults   # non-interactive (CI): skip wizard, accept defaults
```

</details>

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

<details>
<summary>Advanced / occasional commands</summary>

| Command | What it does |
|---|---|
| `dotfiles` | Jump to the source repo (with args, points you at `chezreset` / `chezreinit`). |
| `chez` | Apply without pulling — the building block `chezup` calls. Flags Brewfile drift (packages installed but untracked); never uninstalls. |
| `chezreinit` | Pull, run plain `chezmoi init` to fill in **newly-added** data-model keys, then apply. Keeps existing answers — use after wizard/data-model changes, not to re-choose. |
| `chezreset` | Set up this Mac **as new**: reset chezmoi's persistent state so `run_once_*` (and `run_onchange_*`) hooks fire again, re-ask the full wizard (overriding saved answers), then apply. Confirm-gated; doesn't uninstall packages or delete files. |
| `chezbump` | Routine dependency upgrade (`brew update && brew upgrade` + `mise upgrade`). |
| `chezaudit` | List Homebrew packages installed locally but not tracked in any Brewfile (drift detection; reports only). |
| `chezmirror` | Enforce the Brewfile as truth in the removal direction: preview, then (confirm-gated) `brew bundle cleanup --force` to uninstall everything untracked. |

</details>

## How it works

**`chezup` runs in three phases:**

1. **Update repo** — `git pull --ff-only` in the source dir; reports how many commits arrived.
2. **Review pending changes** — `chezmoi status` lists the drift between the repo and `$HOME` (`A` add, `M` modify, `D` remove). If nothing drifted, it stops here.
3. **Apply** — one confirmation gate, then `chezmoi apply --force`.

It honours `DRY_RUN=1` (print, don't run) and `YES=1` (skip the confirm gate), and passes any trailing arguments through to `chezmoi apply` (e.g. `chezup -v`).

**`install.sh` is a tiny bootstrap** — a hand-written script (it runs via `curl | bash` before the repo exists on disk). It installs only the prerequisites (Xcode CLT, Homebrew, chezmoi, the repo clone), then hands off to the plain-text wizard (`scripts/wizard.sh`), which asks the setup questions (profile, signing mode, optional modules) and feeds them to `chezmoi init --apply` — `--apply` runs the hooks. Re-choose your setup anytime with `chezreset`.

## Repository layout

The repo root splits cleanly into **what chezmoi deploys** (everything under
`src/`, its source directory — see [`.chezmoiroot`](.chezmoiroot)) and **the
tooling that supports it** (everything else at the root, never deployed to
`$HOME`):

```
.chezmoiroot            # one line: "src" — points chezmoi at the src/ subdir
src/                    # ← chezmoi's source dir; everything here deploys to $HOME
  .chezmoi.toml.tmpl    #   chezmoi config + the init-prompt setup wizard
  .chezmoidata/         #   static data: module catalog + profile→Brewfile map
  .chezmoiscripts/      #   ordered run scripts (brew bundle, mise, vscode, macOS defaults…)
  dot_config/           #   → ~/.config (zsh, git, mise, nvim, ghostty, starship, claude…)
  dot_zshenv, …         #   other managed dotfiles (private_dot_ssh/, Library/, …)
packages/               # what to install: core Brewfile + profile/module layers + editor lists
scripts/                # chezup.sh, doctor.sh, bootstrap-auth.sh, lib/log.sh…
install.sh              # tiny bootstrap; hands off to `chezmoi init --apply`
tests/                  # bats suites
docs/                   # deeper guides (apply lifecycle…)
```

Repo tooling reaches the managed hooks and vice-versa across that boundary via
chezmoi's `{{ .chezmoi.workingTree }}` (the repo root) — see
[`docs/lifecycle.md`](docs/lifecycle.md).

The shell verbs (`chezup`, `chezdoctor`, `dotfiles`, …) are defined in [`src/dot_config/zsh/dot_zshrc.tmpl`](src/dot_config/zsh/dot_zshrc.tmpl) and delegate to the scripts in [`scripts/`](scripts).

## Development

```sh
# Lint + parse shell
shellcheck install.sh scripts/*.sh scripts/lib/*.sh

# Run the bats test suites
bats tests/

# Render every template across the profile × modules matrix (dry-run)
PROFILE=personal MODULES=macApps,theme,jvmStack bash scripts/render-check.sh "$PWD"
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs shellcheck, renders every chezmoi template across the profile/modules matrix, runs the bats suites, lints config, checks spelling, resolves Homebrew names on macOS, and enforces Conventional Commit PR titles.

## License

MIT. See [LICENSE](LICENSE).
