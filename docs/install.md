# Installing

One installer covers every machine. `install.sh` is a tiny hand-written
bootstrap fetched via `curl | bash` **before this repo exists on disk**, so it
installs only the prerequisites — Xcode Command Line Tools, Homebrew, chezmoi,
and the repo clone — then hands off to the plain-text setup wizard
([`scripts/bin/wizard.sh`](../scripts/bin/wizard.sh)), which asks the setup
questions and runs `chezmoi init --apply`. See [lifecycle.md](lifecycle.md) for
what `apply` then does.

Every step is idempotent and safe to re-run.

## Scenarios

### Brand-new Mac

One command bootstraps everything and applies:

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

When the wizard finishes, sign in and reload:

```sh
open -a 1Password                                                 # skip if disabled
bash ~/Developer/personal/dotfiles/scripts/bin/bootstrap-auth.sh  # finishes git signing
exec zsh                                                          # reload the managed shell
chezdoctor                                                        # verify everything is healthy
sudo shutdown -r now                                             # reboot to finish macOS defaults
```

### Existing Mac with an older setup

Use the **same installer**. It snapshots any pre-existing legacy dotfiles into a
timestamped backup before taking over (skip with `SKIP_BACKUP=1`), then
converges the machine and runs the [deprecation cleanup](#deprecation-cleanup):

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

Afterwards, reload and sanity-check:

```sh
exec zsh
chezdoctor      # warns about any leftover direnv it couldn't remove
```

### Already set up

Just stay current with [`chezup`](commands.md#everyday) — no installer needed.

## Advanced flags

With no extra arguments `install.sh` runs the wizard. Passing **any** extra
arguments bypasses the wizard and forwards them straight to
`chezmoi init --apply` (for scripted/CI use). It also reads two env vars:

```sh
DOTFILES_REPO=<repo-url> bash install.sh                  # point at a fork
DOTFILES_DIR=<path>      bash install.sh                  # clone somewhere else
SKIP_BACKUP=1            bash install.sh                  # don't snapshot legacy dotfiles
curl -fsSL …/install.sh | bash -s -- --promptDefaults     # non-interactive (CI): skip wizard, accept defaults
```

`install.sh` is **not** generated — edit it directly.

## Deprecation cleanup

On an existing Mac the installer runs a cleanup so you don't carry forward tools
the repo no longer manages. It:

- uninstalls the Homebrew packages this repo dropped (`node`, `temurin@21`,
  `temurin@25`, `direnv`) — language runtimes now come from **mise**; and
- removes the leftover `~/.config/direnv` config.

On a fresh machine that never had the old stack, the cleanup is a silent no-op.
It's implemented as the `run_onchange_after_02c-cleanup-deprecated` hook — see
[lifecycle.md](lifecycle.md).

### Coming from the direnv setup

Runtimes (Java/Node/Python) are now managed by **mise**: global defaults live in
`~/.config/mise/config.toml`, and each project pins its own versions + env vars
in a committed `mise.toml` (its `[env]` block replaces `.envrc`). See
[shell.md](shell.md#runtimes-mise) for the runtime setup.
