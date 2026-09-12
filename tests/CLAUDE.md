# `tests/`

bats, one file per unit. Nothing here is capped, so "it would need a test" is
never an argument against a change.

## Rules

- **Nothing may touch the real home directory.** `setup_sandbox` gives every
  test a throwaway `$HOME` and pins `XDG_CONFIG_HOME`, `XDG_STATE_HOME`,
  `DOT_RUN_ID` and the counters. The library loads from the real repo.
- **Assert with `home_snapshot` diffs**, not lists of paths you expect.
- **Properties, not constants.** `DOT_STATUS_WARN` is asserted not to collide
  with a status bash owns, not to equal 3.
- Dry runs write nothing: snapshot, run, snapshot.
- Guards fire. That matters more than the happy path.
- Hostile input to anything reaching TOML, git config or `defaults`.
- Paths inside `.app` bundles are inputs (`DOT_OP_SSH_SIGN`, `DOT_CODE_BIN`),
  so both branches run on a machine without the app.
- **The root `CLAUDE.md` ban on history does not apply here.** In shipped code
  the bug that produced a rule is noise; in a test it is the specification --
  a guard whose reason is not written down is one the next person deletes.
- **No test may need a terminal.** `fzf` is stubbed, or asked to parse its
  options and exit with `--filter`. Driving it through a pty works by hand and
  was tried: under bats the pty never gets its EOF and the run hangs. The note
  at the end of `wizard.bats` says so, so the next person does not rediscover
  it. The same goes for sleeps -- a test paced by them fails on a loaded
  machine, which is worse than the coverage is worth.
- **A hook that reaches outside `$HOME` gets its tool shadowed on PATH**, never
  skipped: `defaults`, `mise` and `brew` all have stubs here, and that is what
  makes an `apply.sh` nobody could run in CI reachable at all.

## `contract.bats`

What makes the registry-free design safe. It walks the driver's glob, so no
module is exempt, and it enforces every structural limit in the root
`CLAUDE.md`. Adding a manifest field, a hook name, a `lib/` file or a verb
means editing this file. That friction is the point.

It also holds the **cross-file invariants**: the ones whose whole content is
"these files must agree" and which nothing else can catch. A rule of that shape
either gets a test here or it is not a rule -- an unenforced agreement rule is
worth exactly nothing, which is why the prose guards (verb count, bash-5 list)
live here too.

## bats notes

- bats installs its own ERR trap; `lib/dot.sh` checks before installing one.
- End `teardown` with `return 0`.
- `found=$(... | while ...; done || true)`: the last iteration usually ends in
  a false test.
