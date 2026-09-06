# `tests/`

bats, one file per unit. **Uncapped and excluded from the size budget**, so
"it would need a test" is never an argument against a change.

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

## `contract.bats`

What makes the registry-free design safe. It walks the driver's glob, so no
module is exempt, and it enforces every hard limit in the root `CLAUDE.md`.
Adding a manifest field, a hook name, a `lib/` file or a verb means editing this
file. That friction is the point.

It also holds the **cross-file invariants**: the ones whose whole content is
"these files must agree" and which nothing else can catch. The bash-5 list had
already drifted to five places while every comment still said four, which is
what an unenforced agreement rule is worth. A rule of that shape either gets a
test here or it is not a rule.

## bats notes

- bats installs its own ERR trap; `lib/dot.sh` checks before installing one.
- End `teardown` with `return 0`.
- `found=$(... | while ...; done || true)`: the last iteration usually ends in
  a false test.
