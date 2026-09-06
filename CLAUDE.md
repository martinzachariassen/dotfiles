# Working in this repo

Per-directory rules: [`lib/`](lib/CLAUDE.md) · [`core/`](core/CLAUDE.md) ·
[`bin/`](bin/CLAUDE.md) · [`modules/`](modules/CLAUDE.md) ·
[`tests/`](tests/CLAUDE.md)

English everywhere: code, comments, commits, docs.

## Before committing

```sh
make check     # shellcheck, shfmt, bats
```

`make brew-audit` is separate on purpose: it asks Homebrew whether the
Brewfiles still resolve, so it needs the network and its verdict changes when
Homebrew does -- it must never fail a pull request about something else. CI
runs it weekly and files an issue, and on the pull requests that touch a
Brewfile, where the answer is the thing under review.

`install-smoke` is separate for the same reason, and covers what no bats test
can: it runs `install.sh` for real on a fresh runner, on the same clock plus
main and the pull requests that touch the bootstrap. It cannot cover steps 1
and 2 -- a hosted runner already has the Command Line Tools and Homebrew, so
both take their "already installed" branch. **Those two stay a hand test on a
clean Mac.**

The tools `make check` runs are not in `core/Brewfile`; they are the
`dotfiles-dev` module, or `brew bundle --file modules/dotfiles-dev/Brewfile`.

The `Makefile` is the only copy of those commands. Never inline them elsewhere.

## Limits

Structural, not size. There is **no line budget** -- not on the engine, not on
a module, not anywhere. A file that has grown too big is a judgement call at
review time, and a number was only ever a proxy for it that went stale.

What *is* enforced, by `tests/contract.bats`:

| What | Limit |
|---|---|
| `lib/` | 7 files, no subdirectories |
| `bin/dot` | 5 verbs, hardcoded `case` |
| `module.toml` | 1 field: `description` |
| Module hooks | `apply.sh`, `doctor.sh`, `remove.sh` -- closed set |
| Module dirs | `home/` (linked), `data/` (hook-private) -- closed set |

These are shape, not weight: each one is a thing the driver reads, so widening
it changes what the repo *is*. Changing one means editing `contract.bats`,
deliberately. That friction is the point.

## Invariants

- **Nothing deletes a real file.** Symlinks and provably-generated files only.
  The backup tree is never removed.
- **A file the user owns is edited only key-by-key, and given back the same
  way.** `claude-code` merges into `~/.claude/settings.json` and takes back only
  the leaves still holding exactly what it wrote; anything changed since stands.
  Never rewrite such a file wholesale, and never delete one -- ownership is the
  user's, and the only proof you have is a value that still matches.
- **Derive, never record.** No state file. Uninstall is the orphan scan with
  nothing enabled; `fs_repo_links` is the one walk both verbs share.
- **Bash 5 in five places that must agree:** `install.sh` (installs it),
  `core/Brewfile` (keeps it managed), `bin/dot` and `uninstall.sh` (re-exec),
  `lib/dot.sh` (refuses below 5). `contract.bats` holds the five together.
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

The bar is high and the default is **no comment**. Code that needs prose to be
readable should be rewritten instead. Three things earn one:

1. A landmine that looks fine.
2. An invariant a future edit would break -- name the other place that must agree.
3. A road not taken.

One to three lines, and never more than a short paragraph at the top of a file.
Explain **why this decision**, never what bash does.

Cut on sight:

- **History.** No "used to", "the old version did", "once", "was found by".
  Git has it. A rule stands on its reason, not on the bug that produced it.
- **Restating the code.** A comment that paraphrases the line under it.
- **Section banners** that only name what is obviously below.
- **A promise no test keeps.** If a comment says two files must agree, either
  `contract.bats` holds them together or the comment is decoration.
