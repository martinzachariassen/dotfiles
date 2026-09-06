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
- **dasel does not validate.** It stops at a malformed line, keeps what it read,
  exits 0. `cfg_parse_problems` is the guard; `apply` refuses, `doctor` reports.
  `taplo` (core/Brewfile) is the real parser, used by `contract.bats`.
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
