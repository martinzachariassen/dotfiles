# Working in this repo

Per-directory rules: [`lib/`](lib/CLAUDE.md) · [`core/`](core/CLAUDE.md) ·
[`bin/`](bin/CLAUDE.md) · [`modules/`](modules/CLAUDE.md) ·
[`tests/`](tests/CLAUDE.md)

English everywhere: code, comments, commits, docs.

## Before committing

```sh
make check     # shellcheck, shfmt, bats, size budget
```

`make brew-audit` is separate on purpose: it asks Homebrew whether the
Brewfiles still resolve, so it needs the network and its verdict changes when
Homebrew does. CI runs it weekly and files an issue; it never blocks a PR.

The `Makefile` is the only copy of those commands. Never inline them elsewhere.

## Limits

Enforced by `make size` and `tests/contract.bats`. **Over a limit means cutting
something, never raising the number.** Changing a limit means editing the test,
deliberately.

| What | Limit |
|---|---|
| Engine (`install.sh`, `uninstall.sh`, `bin/dot`, `lib/`, `core/`) | 2500 lines |
| Each module directory's shell | 150 lines (sum uncapped) |
| `lib/` | 7 files, no subdirectories |
| `lib/wizard.sh` | 60 lines of code |
| `bin/dot` | 3 verbs, hardcoded `case` |
| `module.toml` | 1 field: `description` |
| Module hooks | `apply.sh`, `doctor.sh`, `remove.sh` -- closed set |
| Module dirs | `home/` (linked), `data/` (hook-private) -- closed set |
| Tests | uncapped, excluded from the budget |

## Invariants

- **Nothing deletes a real file.** Symlinks and provably-generated files only.
  The backup tree is never removed.
- **Derive, never record.** No state file. Uninstall is the orphan scan with
  nothing enabled; `fs_repo_links` is the one walk both verbs share.
- **Bash 5 in four places that must agree:** `install.sh`, `core/Brewfile`,
  `bin/dot` (re-exec), `lib/dot.sh` (refuses below 5).
- **`install.sh` shares nothing.** Plain `echo`, no library: it runs before the
  repo exists.
- **Casks before Homebrew** in `uninstall.sh`, and a failed cask aborts before
  the handoff. Irreversible summaries state counts, not categories.
- **Never end a loop with `cmd && printf`.** A false last test leaves status 1
  and `set -e` kills the caller. Use `if`.
- **Quote user input** before it reaches TOML, git config or `defaults`. Those
  tools accept garbage and exit 0.
- **Dry run and real run print the same words.** Announce intent before acting.

## Comments

Explain **why this decision**, never what bash does. Three things earn one:

1. A landmine that looks fine.
2. An invariant a future edit would break -- name the other place that must agree.
3. A road not taken.

One to three lines. No history ("used to", "the old version did"). No file
header essays. No separate docs file.
