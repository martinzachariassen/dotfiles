# dotfiles

One Mac as code, in bash 5: Homebrew packages, config files symlinked into
`$HOME`, and macOS settings. `dot apply` makes the machine match the repo;
`dot doctor` says, read-only, whether it still does.

This file is the rulebook and the only `CLAUDE.md` in the repo. The reasoning
behind each rule lives in `docs/`. Link to it rather than repeat it here.

## Map

| Path | Holds | Explained in |
|---|---|---|
| `bin/dot` | the CLI: five verbs in a hardcoded `case` | [README](README.md#commands) |
| `lib/` | the engine, sourced and never executed | [architecture](docs/architecture.md) |
| `core/` | phase 1: what every machine gets, plus the `dot` shim | [architecture](docs/architecture.md#three-phases) |
| `modules/<name>/` | phase 2, one directory per module | [modules](docs/modules.md), its own `README.md` |
| `tests/` | bats, one file per unit; `contract.bats` holds the structure | [development](docs/development.md) |
| `install.sh`, `uninstall.sh` | bootstrap and full removal | [uninstall](docs/uninstall.md) |
| `profiles.toml` | wizard presets and the `[user]` identity | [configuration](docs/configuration.md#profiles) |

## Commands

```sh
make check                     # shellcheck, shfmt, bats -- exactly what CI runs
bats tests/<file>.bats         # one suite while iterating
DOT_COLUMNS=76 dot doctor      # regenerate sample output for the docs
bash uninstall.sh --dry-run    # likewise, for docs/uninstall.md
```

- The `Makefile` is the only copy of those commands. Never inline them
  elsewhere.
- Their tools are the `dotfiles-dev` module, not `core/Brewfile`.
- `make brew-audit` and `install-smoke` need the network and run apart from
  PRs; see [development](docs/development.md#what-ci-does-not-run).

## Invariants

- **Nothing deletes a real file.** Only symlinks and files the repo provably
  generated are removed. The backup tree is never removed.
- **A file the user owns is edited key by key, and given back the same way.**
  This covers `~/.claude/settings.json`, and the `enabled` array in
  `config.toml`. Take back only what still holds exactly what was written.
  Never rewrite such a file wholesale.
- **Derive, never record.** There is no state file. Uninstall is the orphan
  scan with nothing enabled.
- **Dry run and real run print the same words.** Announce intent before acting.
  Every write is gated on `DOT_DRY_RUN`, either directly or through `fs_link`,
  `fs_unlink` or `fs_discard`.
- **One owner of the output.** Only `lib/ui.sh` emits colour, a glyph or a
  column. Everything else calls `say`/`ok`/`info`/`warn`/`fail`/`die` with a
  bare label. Every other shipped file is pure ASCII, and `make check` fails on
  one em dash.
- **Exit status is derived, never propagated.** `fail` and `warn` bump tallies,
  and the EXIT trap converts them. A hook that only warned exits
  `DOT_STATUS_WARN`. Never `|| true` on a check.
- **A check that could not run is a third answer, never green.** This is the
  three-state shape `brew_missing` uses.
- **A baked-in path to a binary is an input with that path as its default**
  (`DOT_BREW_BIN`, `DOT_TAPLO_BIN`, `DOT_SSH_ADD`). Without one, the branch a
  test needs is the one the machine never takes.
- **Bash 5 in five places that must agree:**
  - `install.sh` installs it;
  - `core/Brewfile` keeps it managed;
  - `bin/dot` and `uninstall.sh` re-exec into it;
  - `lib/dot.sh` refuses anything below 5.
- **`install.sh` shares nothing.** Plain `echo`, no library: it runs before the
  clone exists.
- **No secret value enters the repo.** API keys are `op://` references in
  `modules/zsh/home/.config/op/env`. Add a line only once its 1Password item
  exists.
- **Quote user input** before it reaches TOML, git config or `defaults`. They
  accept garbage and exit 0.
- **Never end a loop with `cmd && printf`.** Under `set -e` a false last test
  kills the caller. Use `if`.
- **Casks before Homebrew** in `uninstall.sh`. Irreversible summaries state
  counts, not categories.

## Rules by area

### `bin/dot`

- **Five verbs.** A sixth needs a capability no existing verb can reach, not a
  convenience. Options are cheap; verbs are not.
- **Match every option exactly**, and treat anything unknown as fatal:
  `dot apply --dry` must not apply.
- **Read everything before writing anything.** In order: phase 1,
  `cfg_parse_problems`, `modules_require_known`, `modules_preflight`, and only
  then the first link.
- **`__module_arg` sets globals and never prints.** Under `$(...)` its
  `--dry-run` export dies, and the verb acts for real.
- **`run_checks` captures by redirect in the current shell, never `$(...)`.**
  The tallies are shell variables.
- **`remove` order:** hook, then links, then config. The config write is the
  commit point.
- **The transcript:**
  - only `apply`, `add` and `remove` write one, and never on a dry run;
  - it opens after the argument parse;
  - one file per run, twenty kept.
- **No `read -p`**, since the transcript's `sed` holds back a partial line. Ask
  with `say`, then a bare `read`.
- **`--pull` re-execs the pulled `bin/dot`.** Never let it carry on in the old
  process, because bash reads the script lazily.

### `lib/`

- **Seven files, no subdirectories.**
- **Nothing memoises.** `modules_enabled` is read in subshells and hooks are
  separate processes. Once-per-run work lives in `bin/dot`. Cross-process state
  is an exported input (`DOT_RUN_ID`).
- **`config.toml` is written once** (`config_generate`). The only other writers
  are `cfg_module_add` and `cfg_module_remove`. They splice one line, validate
  before the `mv`, and refuse an array not in the generated shape.
- **dasel does not validate** and exits 0 on a truncated file.
  `cfg_parse_problems` guards it, with taplo first.
- **dasel reads `-` as subtraction.** Use bracket syntax via `module_setting`,
  and never build a selector from a name.
- **Directories are never symlinked**, only traversed.
- **The orphan scan reads every module, and only enabled ones claim.**
  `brew_unmanaged` also reads every Brewfile, with formulae and casks as two
  separate lists.
- **The guard lives in the helper:** `fs_unlink` tests `-L`, and `fs_discard`
  tests `-f`.
- **The checkout path may not contain `"`, backtick, `$` or `\`.**
  `core/apply.sh` and `uninstall.sh` bake it into scripts, and `core/doctor.sh`
  greps for it.

### `core/`

- **Phase 1, the same contract as a module.** Keep `apply.sh` near-empty.
- **Nothing that runs before `brew bundle --file core/Brewfile` may use a tool
  listed in it.**
- **A package belongs in `core/Brewfile` only if the machinery runs it or every
  machine needs it.** Name the file that runs it, in a comment.
- **The shim `~/.local/bin/dot` is generated, not linked.** Through a link,
  `BASH_SOURCE` would point at `~/.local/bin`.
- **Doctor checks only what fails silently.** Use `dim`, not `warn`, for
  something true on every machine.

### Module hooks

- **The closed set:**
  - files: `module.toml` (one field, `description`), `Brewfile`, `README.md`;
  - directories: `home/` (linked) and `data/` (hook-private, never linked);
  - hooks: `apply.sh`, `doctor.sh`, `remove.sh`.
- **Modules run alphabetically and cannot depend on each other.**
- **Hooks are executed, never sourced.** Start with `set -euo pipefail` and
  `source "${DOT_ROOT:?}/lib/dot.sh"`.
- **`doctor.sh` never writes**, not even through the tool it asks. `mise ls`
  and `colima status` both create directories. Read the evidence on disk.
- **`remove.sh` exists only for what the sweep cannot see.** It reaches `$HOME`
  through `fs_unlink` or `fs_discard`, never `rm`. It stays silent on a machine
  that never ran the module.
- **Read your own settings with `module_setting` only.** Name every key in the
  module's `README.md` and in `docs/configuration.md`.
- **A check this repo cannot fix needs an off switch:** a setting, or the
  Brewfile line for table-driven checks.
- **For one bad setting, use `fail` rather than `die`**, so the rest still
  runs.
- **A literal shared by several hooks** goes in `data/`, or gets a test that
  the copies agree.

### `tests/`

- **Never touch the real `$HOME`.** `setup_sandbox` gives every test its own.
- **A tool that reaches outside `$HOME` is shadowed on `PATH`**, never skipped.
  That covers `brew`, `defaults`, `mise` and `git`.
- **Assert with `home_snapshot` diffs, and assert properties rather than
  constants.**
- **Guards must fire.** That matters more than the happy path.
- **No test needs a terminal or a sleep.**
- **In tests, the bug a guard exists for is the specification.** Write it down;
  the history ban below does not apply here.

## Limits

These are shape, not size. There is no line budget. `tests/contract.bats`
enforces this table, and changing a row means editing it deliberately.

| What | Limit |
|---|---|
| `lib/` | 7 files, no subdirectories |
| `bin/dot` | 5 verbs, hardcoded `case` |
| `module.toml` | 1 field: `description` |
| Module hooks | `apply.sh`, `doctor.sh`, `remove.sh` -- closed set |
| Module dirs | `home/` (linked), `data/` (hook-private) -- closed set |

## A change lands with its doc

Update the doc in the same commit:

| Changed | Also update |
|---|---|
| A module added, renamed or dropped | the module tables in `README.md` |
| A verb, or an option it takes | `usage()` in `bin/dot`, the command list in `README.md` |
| What a run prints | `docs/architecture.md`, and every sample block showing it |
| A module's settings | that module's `README.md`, and `docs/configuration.md` |
| A limit above | this file, `docs/development.md`, `contract.bats` |
| A rule the driver enforces | this file |

`contract.bats` checks four of these: README module names, verbs in `usage()`
and the README, verb counts in `docs/`, and hook settings in the docs. The rest
is a hand check. Sample output is pasted from a real run, never sketched.

## Comments

The default is no comment. Code that needs prose to be readable gets rewritten
instead. Only two things earn a comment:

1. **A landmine:** code that is right for a reason the next reader would undo.
2. **A cross-file invariant**, naming the other place that must agree. Write it
   only where `contract.bats` holds the two together.

Keep it to one line, three at most. Say why, never what. No history, no
paraphrase of the code, no section banners, no copy of `docs/` or of this file.
`tests/` is the exception for history, as above.

## Commits and pull requests

- **Commit subjects are Conventional Commits:**
  `fix(ui): count what a hook reported`. Types in use: `feat`, `fix`,
  `refactor`, `test`, `docs`, `chore`. The subject says what changed; the body
  says why.
- **Run `make check` before committing.**
- **A PR fills in `.github/pull_request_template.md`** and is titled like its
  commit.
