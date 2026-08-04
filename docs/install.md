# Installing

One installer covers every machine. [`install.sh`](../install.sh) is a tiny
hand-written bootstrap fetched via `curl | bash` **before this repo exists on
disk**, so it installs only the prerequisites — Xcode Command Line Tools,
Homebrew, chezmoi, and the repo clone — then hands off to the setup wizard
([`scripts/bin/wizard.sh`](../scripts/bin/wizard.sh)), which asks the setup
questions and runs `chezmoi init --apply`. See [lifecycle.md](lifecycle.md) for
what `apply` does. Every step is idempotent and safe to re-run.

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
sudo shutdown -r now                                              # reboot to finish macOS defaults
```

### Existing Mac with an older setup

Use the **same installer**. It snapshots any pre-existing legacy dotfiles into a
timestamped backup before taking over (skip with `SKIP_BACKUP=1`), converges the
machine, and runs the [deprecation cleanup](#cleaning-up-drift-on-an-existing-mac):

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

With no arguments `install.sh` runs the wizard. **Any** extra arguments bypass
the wizard and forward straight to `chezmoi init --apply` (for scripted/CI use).
It also reads three environment variables:

```sh
DOTFILES_REPO=<repo-url> bash install.sh                  # point at a fork
DOTFILES_DIR=<path>      bash install.sh                  # clone somewhere else
SKIP_BACKUP=1            bash install.sh                  # don't snapshot legacy dotfiles
curl -fsSL …/install.sh | bash -s -- --promptDefaults     # non-interactive (CI): skip wizard, accept defaults
```

`install.sh` is **not** generated — edit it directly.

## Cleaning up drift on an existing Mac

The installer only ever **adds** — it renders managed files, installs the
Brewfile, and runs `mise install`. It never uninstalls or deletes, so an
existing Mac can carry forward tools, packages, and config the repo no longer
manages (an old `~/.config/direnv`, a dropped `node` formula, leftover Nix
remnants). Reconciling that drift back to the repo is a deliberate, **manual**
step you run when you want to:

- `chezmirror` — remove Homebrew packages, casks, and taps the Brewfiles no
  longer declare (confirm-gated, one at a time), then `brew autoremove` orphaned
  dependencies.
- `chezclean` — remove untracked dotfiles the repo doesn't manage, across the
  top level of `$HOME` (the dangling `~/.nix-profile` symlink, say) and
  `~/.config` (`~/.config/direnv`). Tool-aware, confirm-gated. See
  [lifecycle.md](lifecycle.md#reconciling-untracked-dotfiles-chezclean).

Anything nested deeper than an immediate child is out of `chezclean`'s scope —
remove it once by hand instead (`rm -rf ~/.local/state/nix` for an empty
leftover state dir, for example). On a fresh machine that never had the old
stack, there's nothing to reconcile.

## Work-profile security tooling (storecode)

On the **work** profile the apply also ensures `storecode` — an internal
security tool that guards shell commands — is installed. It ships via its
**own** installer, not Homebrew, so it's never a Brewfile entry and
`chezaudit`/`chezmirror` never flag it; `~/.storecode` sits on the cleanup
keep-list (`cleanup.keepHome`), so `chezclean` never offers to remove it. The
installer command is data-driven in
[`src/.chezmoidata/storecode.toml`](../src/.chezmoidata/storecode.toml)
(`storecode.installCmd`); until it's set, the
`run_onchange_after_05-storecode` hook prints how to finish the install and
exits cleanly — an apply never fails just because storecode isn't wired up yet.
On any non-work profile the hook is a no-op.

### Coming from the direnv setup

Runtimes (Java/Node/Python) are now managed by **mise**: global defaults live
in `~/.config/mise/config.toml`, and each project pins its own versions and env
vars in a committed `mise.toml` (its `[env]` block replaces `.envrc`). See
[shell.md](shell.md#runtimes-mise) for the runtime setup.
