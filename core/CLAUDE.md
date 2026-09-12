# `core/`

Repo rules: [`CLAUDE.md`](../CLAUDE.md) · For a reader:
[Three phases](../docs/architecture.md#three-phases)

Phase 1. Same contract as a module, just first. Keep `apply.sh` near-empty:
core marks the phase boundary, it does not collect special cases.

## Rules

- `core/Brewfile` installs `dasel` and `fzf`. **Nothing that runs before
  `brew bundle --file core/Brewfile` may use a tool listed in it.**
- A package belongs in `core/Brewfile` only if the **machinery** runs it --
  name the file that does, in a comment beside it -- or every machine must have
  it. It lists `bash`: one of the five bash-5 places. The gates `make check`
  runs are not machinery: they are `modules/dotfiles-dev/Brewfile`, so a machine
  that only *uses* the dotfiles does not carry a linter.
- **The shim `~/.local/bin/dot` is generated, not symlinked.** Through a symlink
  `BASH_SOURCE` would point at `~/.local/bin`. `core/doctor.sh` and
  `uninstall.sh` both `grep -F` its exact `DOT_ROOT="<path>"` line.
- Doctor checks only what fails **silently**. "Is git installed" is not a check.
- Everything found must reach `DOT_FAILURES`. Never `|| true` on a doctor call.
- **A checker that could not run is a third answer**, never a verdict about the
  file. `cfg_parse_problems` treats taplo's documented exit 1 as "invalid" and
  anything else as "did not answer" (a rust panic exits 101), because refusing
  to apply over a crashed taplo would lock the machine out of its own config.
  `cfg_unchecked` is how doctor says so. Same shape as `brew_missing`.
- `dim`, not `warn`, for things true on every machine (uncommitted changes). A
  permanently yellow summary is the same bug as a permanently green one.
- Keep distinct causes distinct: shim missing vs. shim not executable.
  `uninstall.sh` tests `-f`, not `-x`: a shim that lost the bit is still ours.
