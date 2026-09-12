# `modules/`

Repo rules: [`CLAUDE.md`](../CLAUDE.md) · For a reader:
[Modules](../docs/modules.md)

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

Nothing else. Lowercase names matching the directory. Modules run
alphabetically and cannot depend on each other.

## Two shapes, one contract

- **Tool modules** manage a tool's config: `home/`, hooks, or both.
- **Package sets** are a Brewfile and nothing else (`apps`, `work-apps`,
  `dotfiles-dev`). Their `description` starts with `Packages:`.

The split is a reading aid, not a flag the driver knows about, so it is only
true while the directory says so. `dev-cli` was listed as a package set until
it grew a `home/` and three hooks; a `Packages:` description on a module that
links a file is a label contradicting the listing next to it.

**A module that owns a tool's config owns its Brewfile line.** Repeating a
`brew` line across modules is fine (`brew bundle` is idempotent) and is the only
way to say "I need this too".

## `data/`

For what a module's **own hooks** read and the user never edits in place --
`claude-code/data/settings.json`, merged into the user's
`~/.claude/settings.json` with `jq`; and `macos-defaults/data/defaults.tsv`,
the table apply writes, doctor compares and remove cuts its domain list from.
Never reaches `fs_pairs`, so nothing links it (`contract.bats` proves this). A
file the **user** should own goes under `home/` at its path in `$HOME`; a file
that is an argument to a hook goes here.

It exists to kill the alternative: the same literal pasted into `apply.sh`,
`doctor.sh` and `remove.sh` with a test to keep the copies honest. One file,
every reader. Every shipped file under `data/` and `home/` is parsed by
`contract.bats` according to its extension, so an unparseable one cannot ship.

What it buys is more than fewer lines. A list a hook types out is a claim
nothing checks, and the cost per line is what makes a hook sample instead of
check: cut from the file, the list cannot go stale and the sample becomes the
whole table.

## `remove.sh`

**Write one only for what the uninstall sweep cannot see.** The four kinds it
exists for, and why each is shaped that way, are in
[docs/modules.md](../docs/modules.md#removesh). Two of them constrain the code
here:

- **A real file the user owns** is taken back leaf by leaf -- only the ones
  still holding exactly what apply wrote, deepest first, pruning only the
  objects this module itself emptied. Never wholesale, never deleted; see the
  root `CLAUDE.md` invariant.
- **Nothing to delete makes the report the deliverable** (`macos-defaults`,
  `dev-cli`). Derive that list, never type it out, and stay silent on a machine
  that never ran the module -- `uninstall.sh` calls every `remove.sh`, enabled
  or not.

## Writing a hook

Hooks are **executed, not sourced**. `bash modules/git/doctor.sh` is exactly
what the driver does.

```sh
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"
```

- Read a module's **own** settings through `module_setting` only -- it is what
  gets the bracket syntax right. The shared `[user]` table is not a module
  setting; `git/apply.sh` reads it with `cfg_get`, and that is the exception.
- **Validate values yourself.** `defaults`, dasel and git config accept
  anything and exit 0.
- `fail` over `die` for one bad setting, so the rest still runs.
- Honour `DOT_DRY_RUN`, or a preview becomes a run: gate on it and `exit 0`
  before the first write, or do the writing through a helper that gates for you
  (`fs_link`, `fs_unlink`, `fs_discard`). `contract.bats` snapshots `$HOME`
  around every `apply.sh` and every `remove.sh` to hold this.
- Warn-only hooks exit `DOT_STATUS_WARN`. Never `|| true`.
- **`doctor.sh` never writes.** `contract.bats` snapshots `$HOME` around every
  one. `colima status` creates `~/.colima` just by being asked, and `mise ls`
  creates `~/.local/share/mise` and `~/.local/state/mise`. Two ways out:
  `containers` asks anyway but only once `~/.colima/default` proves a VM
  exists; `dev-cli` never asks, and reads the install tree instead. The generic
  snapshot only fires on a machine that **has** the tool -- CI has neither --
  so each hook also has a named test pinning its own way out.
- **`remove.sh` reaches a path in `$HOME` through `fs_unlink` or `fs_discard`,
  never `rm`.** The guard lives in the helper. A file the hook itself just
  created outside that tree is its own (`claude-code` cleans up its `mktemp`).
  Report what cannot be reversed (`macos-defaults`).
- A literal duplicated across hooks needs a test that the copies agree
  (`containers`' plugin list, `git`'s ownership header) -- or, when it is data
  rather than one word, a file under `data/` that all of them read.
