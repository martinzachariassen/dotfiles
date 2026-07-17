<div align="center">

<img src="assets/banner.png" alt="martin@dotfiles — chezmoi-managed macOS setup: zsh, Ghostty + Zellij, mise runtimes, Homebrew, Catppuccin Frappé — bootstrapped by one curl | bash and converged with chezup" width="900">

# dotfiles

**The Mac setup of [Martin Zachariassen](https://mlz.no)** — one command turns a fresh
Apple Silicon Mac into a fully configured backend workstation, managed by
[chezmoi](https://chezmoi.io).

[![CI](https://img.shields.io/github/actions/workflow/status/martinzachariassen/dotfiles/ci.yml?branch=main&label=CI&style=flat-square)](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-Apple_Silicon-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![chezmoi](https://img.shields.io/badge/chezmoi-managed-66ccff?style=flat-square)](https://chezmoi.io)
[![zsh](https://img.shields.io/badge/shell-zsh-4EAA25?style=flat-square&logo=zsh&logoColor=white)](#what-you-get)
[![Catppuccin Frappé](https://img.shields.io/badge/Catppuccin-Frapp%C3%A9-f2d5cf?style=flat-square&labelColor=303446)](https://github.com/catppuccin/catppuccin)

[Quick start](#quick-start) · [What you get](#what-you-get) · [Commands](#commands) · [How it works](#how-it-works) · [Repository layout](#repository-layout) · [Documentation](#documentation)

</div>

## About

A personal, single-machine setup: terminal, shell, editors, Homebrew apps,
[mise](https://mise.jdx.dev)-managed runtimes, and macOS defaults, all declared
in one repo. Bootstrap once with `curl | bash`, then keep the machine matching
the repo with a single verb — `chezup`.

- **One-command bootstrap** — [`install.sh`](install.sh) takes a fresh or legacy
  Mac from zero: Xcode CLT → Homebrew → this repo → every package → macOS defaults.
- **Convergent** — `chezmoi apply` reconciles *real installed state* on every
  run; every step is idempotent and safe to re-run.
- **Additive by contract** — an apply only installs what the Brewfiles declare,
  never uninstalls. Removal is [`chezmirror`](#commands)'s job, behind a per-package confirm.
- **No `sudo` lifestyle** — everything runs as your normal user; Homebrew and the
  macOS defaults ask for your password only when they need it.
- **Layered packages** — a core [Brewfile](packages/Brewfile) plus composable
  profile and module layers ([mac-apps, personal, work](packages/)), chosen in a
  plain-text wizard and mapped in `src/.chezmoidata/packages.toml`.
- **Verifiable CI** — every push lints shell, renders the full chezmoi template
  matrix, runs the [bats suites](tests/), and enforces Conventional Commits.

## Quick start

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

Works on both a fresh and an existing Mac: the installer snapshots any legacy
dotfiles into a timestamped backup before taking over (skip with `SKIP_BACKUP=1`)
and runs a [deprecation cleanup](docs/install.md#deprecation-cleanup) so old
tooling isn't carried forward. When the wizard finishes, sign in and reload:

```sh
open -a 1Password                                                  # skip if disabled
bash ~/Developer/personal/dotfiles/scripts/bin/bootstrap-auth.sh   # finishes git signing
exec zsh                                                           # reload the managed shell
chezdoctor                                                         # verify everything is healthy
sudo shutdown -r now                                               # reboot to finish macOS defaults
```

From then on, staying current is one verb:

```sh
chezup    # pull latest → preview the drift → apply
```

> [!NOTE]
> The plain-text wizard replaces chezmoi's own TUI picker, which is unreliable
> under `curl | bash`. It asks with plain prompts, then feeds chezmoi the
> answers as flags. Advanced flags (`DOTFILES_REPO`, `DOTFILES_DIR`,
> `--promptDefaults`) are in [docs/install.md](docs/install.md#advanced-flags);
> coming from the old direnv setup, see the
> [migration note](docs/install.md#coming-from-the-direnv-setup).

## What you get

| Area          | Baseline                                                                                                                  |
| ------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Terminal      | [Ghostty](https://ghostty.org), [Zellij](https://zellij.dev), [Starship](https://starship.rs), Catppuccin Frappé, JetBrainsMono Nerd Font |
| Shell         | zsh with XDG layout, fzf, zoxide, Carapace completions, syntax highlighting, modern CLI aliases                            |
| Editors       | VS Code via Homebrew (extensions in [`packages/vscode-extensions.txt`](packages/vscode-extensions.txt)), Neovim with LazyVim |
| Git           | 1Password SSH signing, delta diffs, useful aliases, pull rebase, rerere                                                    |
| Runtimes      | [mise](https://mise.jdx.dev) for per-project Java/Node/Python; global defaults in `~/.config/mise/config.toml`             |
| iOS / Swift   | Optional `appleDev` module: SwiftLint, SwiftFormat, [xcodes](https://github.com/XcodesOrg/xcodes), xcbeautify, fastlane, SF Symbols — [details](docs/packages.md#optional-modules) |
| Local AI      | Default `macApps` module: Ollama (brew service) plus the Claude and Claude Code apps                                       |
| Apps          | Homebrew-managed core apps, optional Mac app extras, profile-specific personal/work layers                                 |
| macOS         | Keyboard, Finder, Dock, screenshots, TextEdit, and security defaults — [full list](docs/macos.md)                          |

## Commands

Every `chez*` verb is a zsh function defined in
[`src/dot_config/zsh/dot_zshrc.tmpl`](src/dot_config/zsh/dot_zshrc.tmpl),
delegating to a script in [`scripts/bin/`](scripts/bin). Only two of them
matter day to day — the rest are there when you change your setup or manage
package drift. Forget one? `chezhelp` prints the whole list in your terminal.

| Command      | What it does                                                                                       |
| ------------ | -------------------------------------------------------------------------------------------------- |
| `chezup`     | **Converge this Mac to the repo.** Pull latest → preview the drift → apply. The one you run most.  |
| `chezdoctor` | Read-only **health check**: repo, chezmoi, brew, auth, signing, mise, shell layout. Fixes nothing. |

### Changing your setup

| Command     | What it does                                                                                                     |
| ----------- | ----------------------------------------------------------------------------------------------------------------- |
| `chezreset` | Set the Mac up **as new**: reset run-once state, re-ask the full wizard (overriding saved answers), then apply.    |
| `chezreinit`| Fill in **newly-added** setup keys only — keeps every answer already given. Use after a data-model change.         |
| `wizard.sh` | The plain-text setup wizard itself (`chezreset` calls it). Run directly to change answers without a full bootstrap.|

### Packages & drift

| Command     | What it does                                                                                                      |
| ----------- | ------------------------------------------------------------------------------------------------------------------ |
| `chez`      | Apply **without pulling** — the building block `chezup` calls. Flags Brewfile drift; never uninstalls.              |
| `chezdiff`  | Explain what would change in **plain words** — pending repo → `$HOME` writes and local drift. Read-only.            |
| `chezbump`  | Routine dependency upgrade: `brew update && brew upgrade` + `mise upgrade`.                                         |
| `chezaudit` | List Homebrew packages installed locally but **not tracked** in any Brewfile. Reports only.                         |
| `chezmirror`| Enforce the Brewfile as truth in the **removal** direction — preview untracked items, then confirm each removal (`--all` / `YES=1` to batch). |

> [!IMPORTANT]
> **An apply never uninstalls.** It must be safe to run at any time, so it only
> ever *adds* presence. Freshness is `chezbump`'s job; *removal* is
> `chezmirror`'s, always behind a confirm. Full rationale in
> [docs/lifecycle.md](docs/lifecycle.md#convergence-guarantee).

`chezup` honours `DRY_RUN=1` (print every step, run nothing) and `YES=1` (skip
the confirm gate), and forwards trailing args to `chezmoi apply`. If a verb
ever says its script is missing after a repo restructure, the functions
self-heal — details in
[docs/commands.md](docs/commands.md#when-a-command-says-its-script-is-missing).

## How it works

[`install.sh`](install.sh) is a tiny bootstrap fetched via `curl | bash`
**before the repo exists on disk**: it installs only the prerequisites (Xcode
CLT → Homebrew → chezmoi → clone), then hands off to the plain-text wizard,
which feeds your answers to `chezmoi init --apply`.

`chezup` runs in three phases: **update repo** (`git pull --ff-only`), **review
pending changes** (`chezmoi status` — stops here if nothing drifted), then
**apply** (one confirm gate, then `chezmoi apply --force`).

Both paths end in the same `chezmoi apply`, which reconciles real installed
state on every run. What apply does stage by stage — the hook ordering, the
convergence guarantee, and where each piece lives — is in
[docs/lifecycle.md](docs/lifecycle.md).

## Repository layout

The root splits cleanly into **what chezmoi deploys** (everything under `src/`,
its source directory — see [`.chezmoiroot`](.chezmoiroot)) and **the tooling
that supports it** (everything else, never rendered to `$HOME`):

```text
src/            # chezmoi's source dir — everything here deploys to $HOME
packages/       # core Brewfile + profile/module layers + editor lists
scripts/
├── bin/        #   user-facing verbs: chezup, doctor, wizard, macos-defaults…
├── ci/         #   CI + pre-commit checks
└── lib/        #   sourced bash helpers
install.sh      # tiny bootstrap; hands off to `chezmoi init --apply`
tests/          # bats suites
docs/           # topic guides (see Documentation)
```

The full layout, chezmoi naming conventions (`dot_*`, `run_*`, `.tmpl`), and
the `{{ .chezmoi.workingTree }}` path idiom are in
[docs/architecture.md](docs/architecture.md).

## Documentation

Deeper guides live in [`docs/`](docs/) ([index](docs/README.md)):

| Doc                                      | Covers                                                                       |
| ---------------------------------------- | ---------------------------------------------------------------------------- |
| [install.md](docs/install.md)            | Bootstrap scenarios, `install.sh` flags, deprecation cleanup                  |
| [commands.md](docs/commands.md)          | Every verb — `chezup`, `chezdoctor`, and the occasional helpers               |
| [packages.md](docs/packages.md)          | Package tiers, profiles, the module catalog, and the wizard                   |
| [architecture.md](docs/architecture.md)  | The `src/` split, repo layout, and `scripts/` organization                    |
| [lifecycle.md](docs/lifecycle.md)        | What `chezmoi apply` does, stage by stage                                     |
| [macos.md](docs/macos.md)                | Every macOS system setting applied                                            |
| [development.md](docs/development.md)    | Quality gates, the CI matrix, and the bats suites                             |
| [shell.md](docs/shell.md) · [terminal.md](docs/terminal.md) · [editors.md](docs/editors.md) · [ai.md](docs/ai.md) | The configured environment — zsh/CLI/mise/git, Ghostty/Zellij/Starship, VS Code/Neovim, and AI tooling |

## Development

```sh
shellcheck install.sh scripts/bin/*.sh scripts/ci/*.sh scripts/lib/*.sh   # lint shell
bats tests/                                                               # unit tests
pre-commit run --all-files                                                # the full local gate set
```

**Verified in CI.** [`ci.yml`](.github/workflows/ci.yml) lints shell
(`shellcheck`, `shfmt`), checks spelling (`typos`), validates every rendered
JSON/TOML config, renders the full chezmoi template matrix across
profiles and modules, runs the bats suites, resolves Homebrew names on macOS,
and enforces Conventional Commit titles. Full detail in
[docs/development.md](docs/development.md).

## License

[MIT](LICENSE) © [Martin Zachariassen](https://mlz.no)

---

<div align="center">
<sub>Built for a single Apple Silicon Mac · managed by <a href="https://chezmoi.io">chezmoi</a> · converges with one command · <a href="https://mlz.no">mlz.no</a></sub>
</div>
