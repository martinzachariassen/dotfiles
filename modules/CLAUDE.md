# `modules/`

**The directory listing is the registry.** Adding a module is creating a
directory. `tests/contract.bats` walks the same glob the driver walks.

```
modules/<name>/
  module.toml      required -- exactly one field: description
  Brewfile         optional -- phase 2 packages
  home/            optional -- mirrored into $HOME, leaves linked
  data/            optional -- module-private, read by its own hooks, never linked
  apply.sh         optional hook
  doctor.sh        optional hook
  remove.sh        optional hook
  README.md        optional
```

Nothing else. Lowercase names matching the directory. **150 lines of shell per
directory.** Modules run alphabetically and cannot depend on each other.

## Two shapes, one contract

- **Tool modules** manage a tool's config: `home/`, hooks, or both.
- **Package sets** are a Brewfile and nothing else (`apps`, `work-apps`). Their
  `description` starts with `Packages:`.

The split is a reading aid, not a flag the driver knows about, so it is only
true while the directory says so. `dev-cli` was listed here until it grew a
`home/` and two hooks; a `Packages:` description on a module that links a file
is a label contradicting the listing next to it.

**A module that owns a tool's config owns its Brewfile line.** Repeating a
`brew` line across modules is fine (`brew bundle` is idempotent) and is the only
way to say "I need this too".

## `data/`

For what a module's **own hooks** read and the user never edits in place --
`claude-code/data/settings.json`, merged into the user's `~/.claude/settings.json`
with `jq`; `macos-defaults/data/defaults.tsv`, the table apply writes, doctor
compares and remove cuts its domain list from; and `dev-cli/data/go-tools.txt`,
the packages apply installs and doctor looks for the binaries of. Never reaches
`fs_pairs`, so nothing links it (`contract.bats` proves this). A file the USER
should own goes under `home/` at its path in `$HOME`; a file that is an argument
to a hook goes here.

It exists to kill the alternative: the same literal pasted into `apply.sh`,
`doctor.sh` and `remove.sh` with a test to keep the copies honest. One file,
every reader. Every shipped file under `data/` and `home/` is parsed by
`contract.bats` according to its extension, so an unparseable one cannot ship.

What it buys is more than fewer lines. A list a hook types out is a claim
nothing checks: `macos-defaults/remove.sh` named six domains by hand for an
**irreversible** change, and `doctor.sh` sampled six keys because each one cost
a line. Cut from the file instead, the list cannot go stale and the sample
becomes the whole table.

`remove.sh` exists for what the uninstall sweep cannot see: links whose target
is outside `$DOT_ROOT` (`containers`) and generated real files (`git`).

## Writing a hook

Hooks are **executed, not sourced**. `bash modules/git/doctor.sh` is exactly
what the driver does.

```sh
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"
```

- Read settings through `module_setting` only.
- **Validate values yourself.** `defaults`, dasel and git config accept
  anything and exit 0.
- `fail` over `die` for one bad setting, so the rest still runs.
- Honour `DOT_DRY_RUN`, or a preview becomes a run.
- Warn-only hooks exit `DOT_STATUS_WARN`. Never `|| true`.
- **`doctor.sh` never writes.** `contract.bats` snapshots `$HOME` around every
  one. `colima status` creates `~/.colima` just by being asked, and `mise ls`
  creates `~/.local/share/mise` and `~/.local/state/mise`. Two ways out:
  `containers` asks anyway but only once `~/.colima/default` proves a VM
  exists; `dev-cli` never asks, and reads the install tree instead. The generic
  snapshot only fires on a machine that HAS the tool -- CI has neither -- so
  each hook also has a named test pinning its own way out.
- **`remove.sh` uses `fs_unlink` and `fs_discard`, never `rm`.** Report what
  cannot be reversed (`macos-defaults`).
- A literal duplicated across hooks needs a test that the copies agree
  (`containers`' plugin list, `git`'s ownership header) -- or, when it is data
  rather than one word, a file under `data/` that all of them read.
