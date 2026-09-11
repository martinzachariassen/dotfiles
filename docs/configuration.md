# Configuration

`~/.config/dotfiles/config.toml` is the only source of truth for what a machine
gets. It is generated **once**, by `dot config --init`, and belongs to you from
that moment on.

[The file](#the-file) · [When it does not parse](#when-it-does-not-parse) ·
[Enabling and disabling](#enabling-and-disabling) · [Profiles](#profiles) ·
[Per-module settings](#per-module-settings)

## The file

```toml
schema = 1

[user]
name  = "Ada Lovelace"
email = "ada@example.com"

[modules]
enabled = [
  "git",
  "zsh",
]

[settings.git]
signingkey = "ssh-ed25519 AAAA..."
```

Then `dot apply`. The generated file carries comments explaining each table and
listing the available module names; nothing in the tool rewrites it, so those
comments survive.

`[user]` is shared rather than per-module: `modules/git/apply.sh` reads it to
generate `~/.config/git/config.local`. Everything else a module needs lives
under `[settings.<module>]`.

## When it does not parse

Editing the file by hand is supported, so a mistake has to be an error rather
than a run reporting success having installed three modules of four:

- **A name with no matching module** stops the run and prints the real ones.
- **A file that does not parse whole** stops it too. `dasel` reads TOML but
  does not validate it — on a malformed line it stops, keeps what it read and
  exits `0`, silently dropping the rest of the file. So `taplo` is asked first,
  with two heuristics behind it for the machine where phase 1 has not run yet.
- **`schema` must be one this checkout speaks.** Checked, not merely written: a
  version marker that guarantees nothing is worse than none, because it looks
  like a check.

`dot apply` refuses on any of these; `dot doctor` reports them instead.

## Enabling and disabling

```sh
dot add containers --dry-run    # the whole plan, nothing changed
dot add containers              # into the list, then packages, links, apply.sh
dot remove containers           # remove.sh, then unlink, then out of the list
```

`remove` runs in the order `uninstall.sh` uses, and the config write comes last
on purpose — it is the commit point, so anything that failed above it leaves
the module still listed and re-running is the fix.

**Packages stay.** `remove` says so on every run, because "removed" reads as if
they went too. Uninstalling them is `brew uninstall`, and it stays yours —
nothing here can tell which of them you also wanted for something else.

Editing `enabled` by hand instead is still supported, and still leaves things
behind, because nothing then runs the module's `remove.sh`. That is what `dot
doctor`'s orphan report is for; it prints the command to finish the job:

```sh
DOT_ROOT=$PWD DOT_DRY_RUN=1 bash modules/containers/remove.sh   # preview
DOT_ROOT=$PWD bash modules/containers/remove.sh                 # do it
```

`DOT_ROOT` has to be set: every hook sources the library through it.

One thing no route can undo:
**[`macos-defaults`](../modules/macos-defaults/README.md) cannot be put back.**

## Profiles

`dot config --init` offers the profiles in [`profiles.toml`](../profiles.toml)
as starting points for the checklist, plus **`none`**, which skips the picker
and writes an empty list. There is no "custom" profile — hand-assembling a
module list is what the config file is for. Profiles are a first-run
convenience only; `dot apply` never reads `profiles.toml`.

`profiles.toml` also carries a `[user]` table — name, email, and the public
half of the SSH key that signs commits. **The wizard copies these into
`config.toml` and never asks for them**, because none of the three varies by
machine, and a prompt whose answer is always the same is ceremony. The signing
key is safe in a public repo by construction: it is a *public* key, the kind
GitHub already serves at `github.com/<user>.keys`.

Forking this repo means editing those three values first. Left alone, they make
your commits Martin's.

## Per-module settings

A module reads its own settings with `module_setting` and ignores anything it
does not recognise, so an unknown key is never an error:

```toml
[settings.git]
signingkey = "ssh-ed25519 AAAA..."
```

The table name is the module name. Two modules take settings today:
[`git`](../modules/git/README.md) reads `signingkey`, and
[`macos-defaults`](../modules/macos-defaults/README.md) reads `dock_autohide`,
`dock_tilesize` and `screenshot_dir`. Each README lists its keys, their
defaults, and how a bad value is handled.
