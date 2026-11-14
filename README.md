<p align="center">
  <img src=".github/assets/banner.svg" alt="dotfiles: my Mac as code. A terminal shows dot apply installing Discord, with a live progress bar." width="100%">
</p>

<p align="center">
  <a href="https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml"><img src="https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/martinzachariassen/dotfiles" alt="License: MIT"></a>
</p>

<p align="center">
  <a href="#quick-start"><b>Quick start</b></a>
  &nbsp;·&nbsp;
  <a href="#modules"><b>Modules</b></a>
  &nbsp;·&nbsp;
  <a href="#documentation"><b>Documentation</b></a>
  &nbsp;·&nbsp;
  <a href="docs/uninstall.md"><b>Uninstall</b></a>
</p>

Homebrew packages, config files symlinked into `$HOME`, and the few macOS
settings that are not files at all, described in one repo. `dot apply` makes a
machine match it, and `dot doctor` tells you, without changing anything,
whether it still does.

This is my own setup. It is public so you can read it, borrow from it, or fork
it and make it yours.

## Quick start

You need an Apple Silicon Mac running macOS 14 or newer. Nothing else has to be
installed first.

**1. Run the installer.**

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

It installs the Xcode Command Line Tools, Homebrew and bash 5, and clones this
repo to `~/Developer/personal/dotfiles`.

**2. Pick your modules.** A first-run wizard asks which parts of the repo this
machine should have and writes your answer to `~/.config/dotfiles/config.toml`.
From then on, `dot apply` applies it.

**3. Check the result.** `dot doctor` should end with *Everything looks right.*

> **Forking it?** Edit the `[user]` table in [`profiles.toml`](profiles.toml)
> first. The wizard copies that name, noreply email and public signing key into
> your config without asking, so a fork run as-is authors commits as Martin and
> turns on signing with a key whose private half lives only in his 1Password
> vault.

## What it does

| | |
| --- | --- |
| **Installs packages** | Homebrew, with one `Brewfile` per module plus a small core every machine gets. |
| **Links config files** | Symlinks into `$HOME`, so editing `~/.config/git/config` edits the file in this repo. |
| **Runs module hooks** | For what a symlink cannot do: macOS `defaults`, a generated git include, a `jq` merge into `~/.claude/settings.json`. |
| **Reports drift** | `dot doctor` is read-only. A healthy module is one line; a broken one expands to say what. It also names packages installed by hand that no `Brewfile` would put on your next machine. |
| **Takes it back** | [`uninstall.sh`](docs/uninstall.md) removes what the repo added and never a file of yours. |

`dot apply --dry-run` on a Mac that already matches the repo. A module with
nothing to do is one line: what it found, and how long it took.

```
── dot apply ──────────────────────────────── DRY RUN -- nothing will change
    repo         ~/Developer/personal/dotfiles
    config       ~/.config/dotfiles/config.toml
  ✓ packages       5 packages                                           0.2s
  ✓ read           config parses · 10 modules known · 21 hooks parse

── Applying ────────────────────────────────────────────── core + 10 modules
  ✓ core           shim current                                         0.0s
  ✓ apps           10 packages                                          0.2s
  ✓ claude-code    2 packages · 16 links · settings.json holds all 9 …  0.4s
  ✓ cmux           2 packages · 2 links                                 0.2s
  ✓ containers     5 packages · 1 link                                  0.2s
  ✓ dev-cli        10 packages · 2 links · 10 runtimes match mise.lock  0.2s
  ✓ dotfiles-dev   4 packages                                           0.2s
  ✓ git            1 package · 2 links · identity: Martin Zachariasse…  0.3s
  ✓ macos-defaults 45 keys already set                                  0.2s
  ✓ ssh            2 packages · 2 links                                 0.2s
  ✓ zsh            7 packages · 6 links                                 0.3s

── Plan ──────────────────────────────────────────────────────────── dry run
  ✓ changes      none -- this Mac already matches the repo
    Dry run: nothing was changed.
```

A module with something to do opens instead, and shows each change as it
happens: `→ install  cask discord`, then a live bar with speed and time left,
then `✓ installed  cask discord (118 MB)`. A real run ends on `Done` and the
same checks `dot doctor` runs.

`dot doctor` on a machine that is missing one cask and has one stale link:

```
── Checking ────────────────────────────────────────────── core + 10 modules
  ✓ core           packages · xcode · homebrew · dot · PATH · config · repo
  ✗ apps           GUI apps and fonts as casks, plus an opened-once check
      ✗ packages     Cask discord is not installed -- run: dot apply
  ✓ claude-code    packages · files · settings · auth
  ✓ cmux           packages · files
  ✓ containers     packages · files · colima · DOCKER_HOST
  ✓ dev-cli        packages · files · runtimes · gh · gcloud
  ✓ dotfiles-dev   packages
  ✓ git            packages · files
  ✓ macos-defaults defaults · filevault · firewall · updates · browser
  ✓ ssh            packages · files
  ✓ zsh            packages · files · op
  ▲ orphans        unclaimed -- no module ships these any more:
        ~/.claude/skills/dotfiles-test/SKILL.md
        rm them; there is nothing else to undo.
  → unmanaged      2 packages no Brewfile names
        Formula firebase-cli
        Cask curseforge
        add one to a module Brewfile and the next machine gets it too.

── Result ──────────────────────────────────────────────────────────────────
  ✗ 1 problem, 1 warning
      ✗ apps           packages: Cask discord is not installed -- run: dot apply
  ✓ 10 modules clean
    Every check, including the ones that passed: dot doctor --verbose
```

Two promises hold the rest together:

- **Nothing deletes a real file.** A file in the way is moved to
  `~/.local/state/dotfiles/backups/`, and that tree is never removed.
- **Dry run and real run print the same words.** `--dry-run` is the real code
  path with every mutating step turned into a `printf`, so the preview is what
  happens.

## Commands

```
dot apply              Install packages, link configs, run module hooks
dot apply --pull       Fast-forward this repo first, then apply
dot apply --dry-run    Show every intended change, make none
dot add <module>       Enable one module and apply it
dot remove <module>    Undo one module and disable it
dot config             Open the config file in $EDITOR
dot config --init      Create it for the first time (runs the wizard)
dot doctor             Check this machine; read-only
dot doctor --verbose   The same, including every check that passed
dot <command> --help   One command in full; dot --help lists the modules
```

`add` and `remove` take `--dry-run` too. Re-running `dot apply` is safe and
expected: a module with nothing to do is one line, and a second run ends on
`none -- this Mac already matches the repo`. While brew downloads a cask, a
live line shows its progress and the time left; `DOT_PROGRESS=0` turns it off.

<details>
<summary><strong>Updating</strong></summary>

```sh
dot apply --pull
```

It refuses over uncommitted changes and only fast-forwards, then hands over to
the `dot` it just pulled. This updates the *configuration*, not the packages. `apply` runs `brew bundle
--no-upgrade`, so a package a Brewfile gained arrives and a newer version of one
you already have does not. Upgrading is `brew upgrade`, on your schedule.

</details>

<details>
<summary><strong>Configuration</strong></summary>

Everything you choose lives in `~/.config/dotfiles/config.toml`, generated once
by the wizard and yours from then on: your name and email, the list of enabled
modules, and a `[settings.<module>]` table for modules that take options.

Edit it and run `dot apply`, or let `dot add` and `dot remove` edit the module
list for you. They change one line and leave every other byte, comments
included, alone. See [docs/configuration.md](docs/configuration.md).

</details>

## Modules

A module is a directory under [`modules/`](modules/). Enable the ones you want;
the rest stay out of the way.

### Tool modules

These manage a tool's configuration and install the tool as well, so a module
is never half-enabled.

| Module | What it manages |
| --- | --- |
| `git` | [config, aliases, and a generated machine-local include](modules/git/README.md) |
| `ssh` | [client config; keys stay in 1Password's agent](modules/ssh/README.md) |
| `zsh` | [XDG layout, aliases, PATH, `$EDITOR`, starship](modules/zsh/README.md), and API keys as 1Password references |
| `cmux` | the terminal, plus the Ghostty config it reads: Option stays native for Æ/Ø/Å |
| `claude-code` | [the CLI, and keys merged into `~/.claude/settings.json`](modules/claude-code/README.md) |
| `containers` | [Docker via colima](modules/containers/README.md), no Docker Desktop |
| `dev-cli` | [CLI tools and mise-managed language runtimes](modules/dev-cli/README.md) |
| `macos-defaults` | [Dock, Finder, keyboard, screenshots, locale units](modules/macos-defaults/README.md), set imperatively with no files at all |
| `apps` | [GUI casks and fonts](modules/apps/README.md): Raycast, Chrome, VS Code and more, plus which of them have never been opened |

### Package sets

A Brewfile and nothing else: tools this repo installs but does not configure.

| Module | What it installs |
| --- | --- |
| `work-apps` | what an employer's machine needs: Intune, Office, Teams, Slack |
| `dotfiles-dev` | the toolchain `make check` runs, for a machine you develop *this repo* on |

> **Heads up:** [`macos-defaults`](modules/macos-defaults/README.md) is the one
> module nothing can undo. The old values were never read, so they exist
> nowhere, and removing the module names the settings it wrote rather than
> putting them back.

## Documentation

| Document | What is in it |
| --- | --- |
| [Architecture](docs/architecture.md) | The three phases, the link engine, the orphan scan, and why there is no state file |
| [Configuration](docs/configuration.md) | `config.toml`, enabling and disabling modules, profiles, logs and exit status |
| [Modules](docs/modules.md) | The module contract, writing one, and SSH and commit signing |
| [Uninstalling](docs/uninstall.md) | What `uninstall.sh` removes, what it keeps, and why casks go first |
| [Development](docs/development.md) | `make check`, the structural limits CI enforces, and reading a crash |

The rules for changing the repo, for a person or an agent, are in
[`CLAUDE.md`](CLAUDE.md).

## Development

```sh
make check     # shellcheck, shfmt, bats
```

That is the whole list, and exactly what CI runs. Its tools are the
`dotfiles-dev` module rather than part of the core, so install them with
`brew bundle --file modules/dotfiles-dev/Brewfile`. See
[docs/development.md](docs/development.md).

<details>
<summary><strong>Project layout</strong></summary>

```
bin/dot          The CLI: dispatches each verb
lib/             The shared library: config, filesystem, Homebrew, output, wizard
core/            What every machine gets: a Brewfile and its apply/doctor hooks
modules/         One directory per module: Brewfile, home/, hooks, README
tests/           bats suites, plus contract.bats for the repo's structural rules
docs/            The longer explanations linked above
install.sh       The bootstrap, run before the repo exists
uninstall.sh     Takes everything back
profiles.toml    Wizard presets: your identity and the module profiles
```

</details>

## Contributing

Fork freely. This is a personal setup rather than a tool built for others, so
pull requests are not expected, but you are welcome to take whatever is useful.

## License

[MIT](LICENSE)
