# Modules

A module is a directory. **The directory listing is the registry** — there is
no central list to update, because a central list can disagree with the
filesystem. `tests/contract.bats` walks the same glob the driver walks, which
is what makes that safe.

The list of what ships today is in the
[README](../README.md#modules). This page is the contract behind it.

[The contract](#the-contract) · [Two shapes](#two-shapes) ·
[`data/`](#data) · [`remove.sh`](#removesh) ·
[Writing one](#writing-one) ·
[SSH and commit signing](#ssh-and-commit-signing)

## The contract

```
modules/<name>/
├── module.toml     required   description (the only field)
├── Brewfile        optional   packages for this module
├── home/           optional   mirrors $HOME literally; leaf files are symlinked
├── data/           optional   module-private; its own hooks read it, nothing links it
├── apply.sh        optional   imperative, idempotent, run in its own process
├── doctor.sh       optional   read-only checks
├── remove.sh       optional   cleanup the uninstaller cannot derive
└── README.md       optional
```

Those names are the whole vocabulary — `contract.bats` fails on anything else,
because a config file one level too high looks installed and is inert. Names
are lowercase and match the directory. Modules run alphabetically and cannot
depend on each other.

Hooks are **executed, never sourced**, so `bash modules/git/doctor.sh` is
exactly what the driver does. Adding a module is creating the directory and
writing the one line of `module.toml`.

## Two shapes

- **Tool modules** manage a tool's config: `home/`, hooks, or both. Config and
  package are never split across two modules, so a module is never
  half-enabled.
- **Package sets** are a Brewfile and nothing else. Their `description` starts
  with `Packages:`, and `dot apply` labels them `packages only` as it goes.

The split is descriptive, not enforced — the shapes are identical to the driver
and differ only to the reader — so it is only true while the directory says so.
`dev-cli` was listed as a package set until it grew a `home/` and three hooks;
a `Packages:` description on a module that links a file is a label
contradicting the listing next to it. A module can cross the line by growing,
and the honest move is then to relabel it.

`dotfiles-dev` is the odd package set: the other two are software you use, and
it is software the repo's own tests need. It sits here rather than in
`core/Brewfile` because a machine that merely *uses* the dotfiles should not
carry a linter.

**A module that owns a tool's config owns its Brewfile line.** Repeating a
`brew` line across modules is fine — `brew bundle` is idempotent — and is the
only way to say "I need this too".

## `data/`

For what a module's **own hooks** read and the user never edits in place:
`claude-code/data/settings.json`, merged into `~/.claude/settings.json` with
`jq`, and `macos-defaults/data/defaults.tsv`, the table apply writes, doctor
compares and remove cuts its domain list from. Nothing links it, and
`contract.bats` proves so.

A file the *user* should own goes under `home/` at its path in `$HOME`; a file
that is an argument to a hook goes here. It exists to kill the alternative: the
same literal pasted into `apply.sh`, `doctor.sh` and `remove.sh` with a test to
keep the copies honest. A list a hook types out is a claim nothing checks; cut
from a file, the list cannot go stale and a sample becomes the whole table.

## `remove.sh`

It exists for what the uninstall sweep cannot see. Four kinds, and the third is
the one to be careful with:

1. **Links whose target is outside the repo** (`containers`).
2. **Real files this repo generated**, proven by a header it greps for
   (`git`).
3. **A real file the user owns that a module merged into** (`claude-code`, into
   `~/.claude/settings.json`). Take back only the leaves still holding exactly
   what apply wrote, deepest first, and prune only the objects this module
   itself emptied. Anything changed since stands. Never rewrite the file
   wholesale, and never delete it.
4. **Nothing to delete, so the report is the deliverable.** `macos-defaults`
   changed settings that were never files and cannot be put back, and `dev-cli`
   downloaded into directories full of other projects' toolchains. Both name
   what is left rather than guessing which of it was theirs, and both derive
   that list rather than typing it out. Both stay silent on a machine that
   never ran them — `uninstall.sh` calls every `remove.sh`, enabled or not.

## Writing one

```sh
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"
```

- Read the module's **own** settings through `module_setting` only — it is what
  gets dasel's bracket syntax right. The shared `[user]` table is not a module
  setting; `git/apply.sh` reads it with `cfg_get`, and that is the exception.
- **Validate values yourself.** `defaults`, dasel and git config accept
  anything and exit `0`.
- `fail` over `die` for one bad setting, so the rest still runs.
- **Honour `DOT_DRY_RUN`, or a preview becomes a run.** Gate on it and `exit 0`
  before the first write, or write through a helper that gates for you
  (`fs_link`, `fs_unlink`, `fs_discard`).
- Warn-only hooks exit `DOT_STATUS_WARN`. Never `|| true`.
- **`doctor.sh` never writes.** `colima status` creates `~/.colima` just by
  being asked, and `mise ls` creates two directories under `~/.local`; both
  modules have a named test pinning their way around it.
- **`remove.sh` reaches a path in `$HOME` through `fs_unlink` or `fs_discard`,
  never `rm`.** The guard lives in the helper.

The full rules, with the reason behind each, are in
[`modules/CLAUDE.md`](../modules/CLAUDE.md).

## SSH and commit signing

There are no private keys on this machine. 1Password holds them and exposes an
agent socket; `ssh` asks that agent to sign, and the key never leaves the
vault. `modules/ssh` is the one line of config that points at it:

```
Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

That path is the same on every Mac — `2BUA8C4S2C` is AgileBits' Apple team ID,
not something per-user — which is why it can be tracked rather than generated.
The machine-local override `~/.ssh/config.local` is `Include`d **first**, so
anything in it wins: ssh takes the first value it obtains for each keyword.

Commit signing rides on the same agent and is set up by
[`modules/git`](../modules/git/README.md).

One step cannot be automated: **1Password → Settings → Developer → "Use the SSH
agent"**. Until it is ticked the socket does not exist, and the failure never
mentions SSH config — `git push` reports `Permission denied (publickey)`, which
reads as a key problem and sends you hunting through a key directory that is
empty on purpose. `modules/ssh/doctor.sh` checks the socket, so `dot doctor`
says so plainly instead.
