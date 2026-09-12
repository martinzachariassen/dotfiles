# dotfiles

My Mac as code: Homebrew packages, config files symlinked into `$HOME`, and the
few system settings that are not files at all. One command sets up a fresh
machine, and `dot doctor` says whether it stayed set up.

[![ci](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml)

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

That installs the Xcode Command Line Tools, Homebrew and bash 5, clones this
repo to `~/Developer/personal/dotfiles`, and asks which parts of it this machine
should have. From then on, one command applies the answer: `dot apply`.

Apple Silicon and macOS 14 or newer. Nothing else has to be installed first.

This is Martin's own machine setup, public so it can be read and forked, not a
tool built for someone else's. Fork it freely — pull requests aren't expected.

> **Forking it?** Edit the `[user]` table in
> [`profiles.toml`](profiles.toml) first. The first-run wizard copies that
> name, noreply email and public signing key into your config without asking,
> so a fork run as-is authors commits as Martin and turns on signing with a key
> whose private half lives only in his 1Password vault.

## What it does

- **Installs packages** with Homebrew — one `Brewfile` per module, and a small
  core every machine gets.
- **Links config files** into `$HOME`. They are symlinks, so editing
  `~/.config/git/config` edits the file in this repo.
- **Runs per-module hooks** for what a symlink cannot do: macOS `defaults`, a
  generated git include, a `jq` merge into `~/.claude/settings.json`.
- **Reports drift** with `dot doctor`, which changes nothing. A module with
  nothing wrong is one line; one with something wrong expands to say what.
- **Takes it all back** with [`uninstall.sh`](docs/uninstall.md).

```
── Checking ─────────────────────────────────────────────── core + 9 modules
  ✓ core           the repo, the shim, the config
  ✓ apps           Packages: GUI apps and fonts, installed as Homebrew casks
  ✓ claude-code    Claude Code CLI and its status line
  ✓ cmux           cmux terminal config -- Option key stays native macOS input
  ✓ containers     Docker via colima (a Linux VM, no Docker Desktop)
  ✓ dev-cli        Development CLI tools, plus mise-managed language runtimes
  ✓ git            Git config, aliases, and a machine-local include
  ✓ macos-defaults macOS system preferences (Dock, Finder, keyboard)
  ✓ ssh            SSH client config; keys come from the 1Password agent
  ✓ zsh            zsh with XDG layout, aliases, PATH and prompt
  ✓ orphans        none

── Result ──────────────────────────────────────────────────────────────────
  ✓ Everything looks right.
```

Two promises hold the rest together. **Nothing deletes a real file** — a file
in the way is moved to `~/.local/state/dotfiles/backups/`, and that tree is
never removed. **Dry run and real run print the same words**, because
`--dry-run` is the real code path with every mutating helper turned into a
`printf`.

## Commands

```
dot apply              Install packages, link configs, run module hooks
dot apply --dry-run    Show every intended change, make none
dot add <module>       Enable one module and apply it
dot remove <module>    Undo one module and disable it
dot config             Open the config file in $EDITOR
dot config --init      Create it for the first time (runs the wizard)
dot doctor             Check this machine; read-only
dot doctor --verbose   The same, including every check that passed
```

`add` and `remove` take `--dry-run` too. Re-running `dot apply` is safe and
expected; it is also the update path:

```sh
git -C ~/Developer/personal/dotfiles pull && dot apply
```

It updates the *configuration*, not the packages. `apply` runs `brew bundle
--no-upgrade`, so a package a Brewfile gained arrives and a newer version of
one you have does not. Upgrading is `brew upgrade`, on your schedule.

Removing it *all* again is [`uninstall.sh`](docs/uninstall.md), not a verb of
its own.

## Configuration

One file, `~/.config/dotfiles/config.toml`, generated once by the wizard and
yours from that moment on: your name and email, the list of enabled modules,
and a `[settings.<module>]` table for the modules that take options. Edit it
and run `dot apply`, or let `dot add` and `dot remove` edit the list for you —
they splice one line and copy every other byte through, comments included.

The file itself, and what happens when it does not parse, is in
[docs/configuration.md](docs/configuration.md).

## Modules

A module is a directory under [`modules/`](modules/). What *enabling* one means
to you splits in two, though both are the same shape to the driver.

**Tool modules** manage a tool's configuration and install the tool as well, so
a module is never half-enabled.

| Tool module | What it manages |
|---|---|
| `git` | [config, aliases, and a generated machine-local include](modules/git/README.md) |
| `ssh` | [client config; keys stay in 1Password's agent](docs/modules.md#ssh-and-commit-signing) |
| `zsh` | XDG layout, aliases, PATH, `$EDITOR`, starship |
| `cmux` | the terminal, plus the Ghostty config it reads: Option stays native for Æ/Ø/Å |
| `claude-code` | [the CLI, and keys merged into `~/.claude/settings.json`](modules/claude-code/README.md) |
| `containers` | [Docker via colima](modules/containers/README.md), no Docker Desktop |
| `dev-cli` | [CLI tools and mise-managed language runtimes](modules/dev-cli/README.md) |
| `macos-defaults` | [Dock, Finder, keyboard, screenshots](modules/macos-defaults/README.md) — imperative, no files at all |

**Package sets** are a Brewfile and nothing else: a shopping list for tools this
repo installs but does not configure.

| Package set | What it installs |
|---|---|
| `apps` | GUI casks and fonts: Raycast, Chrome, VS Code, … |
| `work-apps` | what an employer's machine needs: Intune, Office, Teams, Slack |
| `dotfiles-dev` | the toolchain `make check` runs, for a machine you develop *this repo* on |

One thing no route can undo:
**[`macos-defaults`](modules/macos-defaults/README.md) cannot be put back.**

## Documentation

| Document | What is in it |
|---|---|
| [Architecture](docs/architecture.md) | The three phases, the link engine, the orphan scan, and why there is no state file |
| [Configuration](docs/configuration.md) | `config.toml`, enabling and disabling modules, profiles, logs and exit status |
| [Modules](docs/modules.md) | The module contract, writing one, and SSH and commit signing |
| [Uninstalling](docs/uninstall.md) | What `uninstall.sh` removes, what it keeps, and why casks go first |
| [Development](docs/development.md) | `make check`, the structural limits CI enforces, and reading a crash |

Design rules per directory live in the `CLAUDE.md` files:
[`lib/`](lib/CLAUDE.md) · [`bin/`](bin/CLAUDE.md) · [`core/`](core/CLAUDE.md) ·
[`modules/`](modules/CLAUDE.md) · [`tests/`](tests/CLAUDE.md).

## Development

```sh
make check     # shellcheck, shfmt, bats
```

That is the whole list, and exactly what CI runs. The tools it needs are the
`dotfiles-dev` module rather than part of the core, so install them with
`brew bundle --file modules/dotfiles-dev/Brewfile`. See
[docs/development.md](docs/development.md).

## License

[MIT](LICENSE).
