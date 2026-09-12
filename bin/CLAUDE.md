# `bin/`

Repo rules: [`CLAUDE.md`](../CLAUDE.md) · For a reader:
[Commands](../README.md#commands)

One file, `bin/dot`. **Five verbs, hardcoded `case`:** `apply`, `add`,
`remove`, `config`, `doctor`. A sixth goes elsewhere: a user command into a
module's `home/.local/bin/`, full removal into `uninstall.sh`.

The cap was three. `add` and `remove` raised it once, deliberately, because
switching a module *off* had no path at all: `apply` walks only the enabled
list, `doctor` never reaches a disabled module, and `uninstall.sh` is
all-or-nothing. A sixth verb needs the same argument -- a capability no
existing verb can reach -- not a convenience.

## Rules

- **`run_checks` is shared by `doctor` and the tail of `apply`.** Not a sixth
  verb: `apply` must end by observing the machine, not by reporting what it
  attempted. Safe because `contract.bats` proves no `doctor.sh` writes to
  `$HOME`. Skipped under `--dry-run`, where every check would report drift the
  run deliberately did not fix.
- **`run_checks` captures each group; `apply`'s module loop streams.** A report
  is read afterwards, so it can be collapsed to one line per healthy module; a
  `brew bundle` that takes two minutes has to be visible while it runs. The
  capture is a redirect in the **current** shell, never `$(...)`: the tallies
  are shell variables and a subshell would drop them.
- **`doctor` may give a count now.** It used not to, because a hook's three
  problems came back as one rolled-up exit status and a summary may not
  contradict the lines above it. `ui_group` reads the hook's own records, so
  the number and the lines are the same evidence. `--verbose` prints every
  check, including the ones that passed.
- **`modules_preflight` runs after validation and before the first link.**
  Everything above it only reads.
- **The transcript writer must be drained.** `__transcript_start` sets fds 3/4
  and `__DOT_TEE_PID`; `lib/dot.sh`'s EXIT trap restores and `wait`s. Without
  it bash exits unreaped and the log loses the lines naming the failure.
- **It is one `sed`, not a `tee`.** `lib/ui.sh` settles colour before this
  redirect exists, so a plain `tee` wrote every escape sequence into the log.
  `h` keeps the raw line, the substitution strips it, `w` puts the clean copy
  in the file and `g` brings the raw one back for the terminal. One process, so
  the trap's single `wait` still drains everything.
- **Once-per-run work lives here.** Nothing inside `modules_enabled` can
  memoise, so validation (`cfg_parse_problems`, then `modules_require_known`)
  runs here, once, before anything is touched. `doctor` reports both instead.
- **`add` and `remove` gate before they touch anything.** `__module_gate`
  checks the config is editable *first*: unlinking a module and then finding
  the list cannot be updated leaves the machine and the file disagreeing.
- **`remove` runs the hook before the links**, the order `uninstall.sh` uses,
  and writes the config *last* -- that write is the commit point, so a failure
  above it leaves the module listed and re-running is the fix.
- **`__module_arg` sets globals; it must not print its answer.** `x=$(...)`
  runs in a subshell, where its `--dry-run` export would be lost and the verb
  would go on to act for real.
- **`__DOT_EXIT_WARN=0`.** Top level, not a hook: `dot doctor && ...` must
  survive an orphaned link.
- **Bash-5 re-exec** into `/opt/homebrew/bin/bash` stays at the top.
- **The transcript belongs to the verbs that change the machine:** `apply`,
  `add`, `remove`. Not `config`, which hands the terminal to `$EDITOR` -- a tee
  in the way makes `vi` unusable. Not `doctor`, advertised read-only and also
  run as the tail of `apply`, where a second transcript would nest inside the
  first. Never under `--dry-run`. `uninstall.sh` removes `logs/` and must keep
  agreeing they are ours.
- **`__transcript_start` comes after the argument parse**, never before:
  `--dry-run` is settled there, and a dry run opens no transcript.
- **One file per run, `<timestamp>-<verb>.log`, twenty kept.** Not one per day
  appended: a run opens and closes by printing its `log` line, and that path is
  only worth naming if it holds that run and nothing else. The timestamp
  leads and is fixed width, so the rotating sort ignores the suffix. The twenty
  are one budget for the directory, not per verb, and the `touch` comes before
  the `tee` so this run is one of them by construction.
- Match every option exactly; anything unknown is fatal. `dot apply --dry`
  must not apply for real.
- Phase 1 first. `brew_bundle` failure becomes a `die` here so the error names
  the Brewfile.
- The wizard never runs under `--dry-run`.
- Overridable paths are printed in `usage`, never baked into the heredoc.
