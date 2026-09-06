# `bin/`

One file, `bin/dot`. Engine budget. **Three verbs, hardcoded `case`:** `apply`,
`config`, `doctor`. A fourth goes elsewhere: a user command into a module's
`home/.local/bin/`, removal into `uninstall.sh`.

## Rules

- **`run_checks` is shared by `doctor` and the tail of `apply`.** Not a fourth
  verb: `apply` must end by observing the machine, not by reporting what it
  attempted. Safe because `contract.bats` proves no `doctor.sh` writes to
  `$HOME`. Skipped under `--dry-run`, where every check would report drift the
  run deliberately did not fix.
- **`modules_preflight` runs after validation and before the first link.**
  Everything above it only reads.
- **The transcript `tee` must be drained.** `cmd_apply` sets fds 3/4 and
  `__DOT_TEE_PID`; `lib/dot.sh`'s EXIT trap restores and `wait`s. Without it
  bash exits unreaped and the log loses the lines naming the failure.
- **Once-per-run work lives here.** Nothing inside `modules_enabled` can
  memoise, so validation (`cfg_parse_problems`, then `modules_require_known`)
  runs here, once, before anything is touched. `doctor` reports both instead.
- **`__DOT_EXIT_WARN=0`.** Top level, not a hook: `dot doctor && ...` must
  survive an orphaned link.
- **Bash-5 re-exec** into `/opt/homebrew/bin/bash` stays at the top.
- **The transcript redirect belongs to `apply` only.** `dot config` must print
  nothing but the editor's output; no doctor hook may write inside `$HOME`.
  Never under `--dry-run`. `uninstall.sh` removes `logs/` and must keep
  agreeing it is ours.
- **Twenty logs, and the `touch` comes before the `tee`.** This run has to be
  one of the twenty by construction rather than by racing the async redirect.
- Match every option exactly; anything unknown is fatal. `dot apply --dry`
  must not apply for real.
- Phase 1 first. `brew_bundle` failure becomes a `die` here so the error names
  the Brewfile.
- The wizard never runs under `--dry-run`.
- Overridable paths are printed in `usage`, never baked into the heredoc.
