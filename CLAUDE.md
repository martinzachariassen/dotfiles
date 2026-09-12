# Working in this repo

Per-directory rules: [`lib/`](lib/CLAUDE.md) · [`core/`](core/CLAUDE.md) ·
[`bin/`](bin/CLAUDE.md) · [`modules/`](modules/CLAUDE.md) ·
[`tests/`](tests/CLAUDE.md)

English everywhere: code, comments, commits, docs.

## Docs

`README.md` is the overview and stays short; the depth lives in
[`docs/`](docs/), and a module explains itself in its own `README.md`.

**`docs/` explains, a `CLAUDE.md` constrains.** Where both would say the same
thing, the prose belongs in `docs/` and the `CLAUDE.md` keeps the rule and a
link to it. Two copies of one rule is the pair that stops agreeing.

**A change lands with its doc in the same commit.** What to touch:

| Changed | Also update |
|---|---|
| A module added, renamed or dropped | the module tables in `README.md` |
| A verb, or an option it takes | `usage()` in `bin/dot`, the command list in `README.md` |
| What a run prints | `docs/architecture.md`, and every sample block showing it |
| A module's settings | that module's `README.md`, and `docs/configuration.md` |
| A limit in the table below | that table, `docs/development.md`, `contract.bats` |
| A rule the driver enforces | the `CLAUDE.md` of the directory it lives in |

`contract.bats` catches three of those and no more: a module the README never
names, a verb missing from `usage()` or the README, and prose in `docs/` naming
a verb count `bin/dot` no longer has. The rest is a hand check, so a doc claim
worth keeping is worth a test in `contract.bats`.

**Sample output is pasted from a real run**, never sketched: regenerate it with
`DOT_COLUMNS=76 dot doctor` or `bash uninstall.sh --dry-run` rather than
editing a glyph or a column by hand.

## Before committing

```sh
make check            # shellcheck, shfmt, bats -- exactly what CI runs
bats tests/ui.bats    # one file, while iterating
```

Commit subjects are conventional -- `fix(ui): count what a hook reported` --
with `feat`, `fix`, `refactor`, `test`, `docs` and `chore` the types in use.
The subject says what changed; the body says why, at whatever length the reason
needs.

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
- **One owner of the output.** `lib/ui.sh` alone emits colour, a glyph or a
  column; everywhere else calls `say`/`ok`/`info`/`warn`/`fail`/`die` with a
  bare label and lets it pad. That keeps every other shipped script under
  `lib/`, `bin/`, `core/` and `modules/` **pure ASCII** -- one em dash in a
  message fails `make check`.
- **Exit status is derived, never propagated.** `fail` and `warn` bump tallies
  and the EXIT trap converts them; a hook that only warned exits
  `DOT_STATUS_WARN`. Never `|| true` on a check: it swallows the finding and
  the status together.
- **A baked-in path to a binary is an input with that path as its default**
  (`DOT_BREW_BIN`, `DOT_TAPLO_BIN`, `DOT_CODE_BIN`, `DOT_OP_SSH_SIGN`;
  `DOT_COLOR`, `DOT_ASCII` and `DOT_COLUMNS` do it for the terminal). Without
  one, the branch a test needs is the one the machine running it never takes.
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
2. An invariant a future edit would break -- name the other place that must
   agree.
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
