# `lib/`

Sourced, never executed. **7 files, no subdirectories.**

| File | Owns |
|---|---|
| `dot.sh` | `$DOT_ROOT`, `DOT_RUN_ID`, bash-5 guard, ERR/EXIT traps |
| `ui.sh` | `say`/`ok`/`warn`/`fail`/`die`, `fold_status`, the tallies |
| `config.sh` | reading and generating `config.toml` |
| `fs.sh` | linking, backups, orphan scan |
| `modules.sh` | discovery, enablement, hook running |
| `brew.sh` | `brew bundle`, and the read-only `brew_check` doctor uses |
| `wizard.sh` | first-run picker -- **60 lines of code** |

## Rules

- **`config.toml` is written once** (`config_generate`). Every TOML writer drops
  comments; nothing may rewrite it.
- **One exception, and it is the narrowest available:** `cfg_module_add` and
  `cfg_module_remove` splice a single line into the `enabled` array and copy
  every other byte through. Same trade as `claude-code` with
  `~/.claude/settings.json` -- the file is the user's, so the only thing that
  may be touched is what this repo demonstrably wrote itself.
  `cfg_enabled_editable` is the proof: an array not in the generated shape
  (`  "name",` per line) makes them **refuse**, never reformat. Hand-editing
  stays supported, which is the whole reason refusing is the answer.
- **The replacement is validated before the `mv`.** After it there is nothing
  to roll back to. `DOT_TAPLO_BIN` is the input that makes that branch
  reachable in a test.
- **dasel does not validate.** It stops at a malformed line, keeps what it read,
  exits 0. `cfg_parse_problems` is the guard; `apply` refuses, `doctor` reports.
  It asks `taplo` (core/Brewfile) first -- a real parser -- and falls back to
  two heuristics only where phase 1 has not run yet. `DOT_TAPLO_BIN` is the
  input that makes that fallback reachable on a machine that has taplo.
- **`schema` is checked, not just written.** `DOT_CONFIG_SCHEMA` is the one this
  checkout speaks; `cfg_parse_problems` refuses anything else. A version marker
  that guarantees nothing is worse than none -- it looks like a check.
- **`brew_missing` has three answers**, not two: satisfied, missing, and *could
  not be checked*. The third must never render as green.
- **`modules_preflight` parses every hook before `$HOME` is touched.** A syntax
  error used to surface halfway through an apply that had already relinked.
- **dasel reads `-` as subtraction.** Only bracket syntax: `settings["x-y"].key`.
  Always go through `module_setting`. Never build a selector from a table name.
- **Everything is read as `-o yaml`**; `__cfg_unquote` undoes exactly `""` and
  single-quoting. Do not add YAML escapes.
- User input reaches the file only through `__cfg_quote`.
- **Directories are never symlinked**, only traversed.
- **The orphan scan reads all modules; only enabled ones claim.** Narrow the
  scan and you hide the disabled-module links it exists to find.
- **Its roots are the ancestors too, and it reaches one level past each.** A
  file deleted from the repo takes its directory out of the declared set, and
  the link it left would sit where nothing looks. `$HOME` stays at one level:
  its children belong to every tool on the machine.
- `fs_unlink` tests `-L`, `fs_discard` tests `-f`. The guard is in the helper,
  never the caller.
- **Nothing can memoise.** `modules_enabled` is read in subshells; hooks are
  separate processes. Once-per-run work lives in `bin/dot`. Cross-process state
  is an exported input (`DOT_RUN_ID`), not a remembered value.
- `lib/dot.sh` refuses a checkout path containing `"`, backtick, `$` or `\`.
  Three places bake it into generated script; two `grep -F` for it.

## Status

- `fail` bumps `DOT_FAILURES`, never exits. The EXIT trap converts the tally.
- `warn` bumps `DOT_WARNINGS`, never changes the exit status at top level.
- A hook that only warned exits `DOT_STATUS_WARN` (3, not 2: bash owns 2 for
  syntax errors). Drivers fold it back with `fold_status`. Tests assert the
  property, not the number.
- The ERR trap is guarded on `BASH_SUBSHELL == 0` and on no existing ERR trap
  (bats installs its own).
