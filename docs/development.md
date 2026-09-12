# Development

```sh
make check     # shellcheck, shfmt, bats
```

That is the whole list, and exactly what CI runs — the commands live in the
`Makefile` and nowhere else, so a workflow cannot grow a second copy free to
disagree with the first. Individually: `make lint`, `make fmt` (rewrites
files), `make test`.

The tools are deliberately **not** in `core/Brewfile`, which is machinery only.
They are the `dotfiles-dev` module, and its Brewfile stands alone:

```sh
brew bundle --file modules/dotfiles-dev/Brewfile
```

[What CI does not run](#what-ci-does-not-run) ·
[The structural limits](#the-structural-limits) ·
[Layout](#layout) · [When something breaks](#when-something-breaks) ·
[Bash 5](#bash-5)

## What CI does not run

`make brew-audit` and the `install-smoke` workflow are separate on purpose:
both need the network and change verdict for reasons outside any one pull
request, so neither may fail a PR about something else.

- **`make brew-audit`** asks Homebrew whether the Brewfiles still resolve. It
  runs weekly and files an issue, and on the pull requests that touch a
  Brewfile, where the answer is the thing under review.
- **`install-smoke`** runs `install.sh` for real on a fresh runner, on the same
  clock plus `main` and the pull requests that touch the bootstrap.

`install-smoke` cannot cover steps 1 and 2 — a hosted runner already has the
Command Line Tools and Homebrew, so both take their "already installed" branch.
**Those two stay a hand test on a clean Mac.**

## The structural limits

There is no line budget, not on the engine and not on a module. A file that has
grown too big is a judgement call at review time, and a number was only ever a
proxy for it that went stale.

What CI enforces is *shape*, in `tests/contract.bats`:

| What | Limit |
|---|---|
| `lib/` | 7 files, no subdirectories |
| `bin/dot` | 5 verbs, hardcoded `case` |
| `module.toml` | 1 field: `description` |
| Module hooks | `apply.sh`, `doctor.sh`, `remove.sh` — closed set |
| Module dirs | `home/` (linked), `data/` (hook-private) — closed set |

Each is a thing the driver reads, so widening one changes what the repo *is*,
and each means editing `contract.bats` to do it. That friction is the point.

`contract.bats` also holds the cross-file invariants — the rules whose whole
content is "these files must agree", which nothing else can catch. Several are
about the documentation: it fails if a module goes unmentioned in the README,
if a verb is missing from the command list there, or if prose anywhere in
`docs/` names a verb count that `bin/dot` no longer has.

## Layout

| Directory | What lives there | Rules |
|---|---|---|
| `bin/` | `dot`, the CLI and its five verbs | [`bin/CLAUDE.md`](../bin/CLAUDE.md) |
| `lib/` | the engine, sourced and never executed | [`lib/CLAUDE.md`](../lib/CLAUDE.md) |
| `core/` | phase 1: the packages and the shim every machine gets | [`core/CLAUDE.md`](../core/CLAUDE.md) |
| `modules/` | phase 2, one directory per module | [`modules/CLAUDE.md`](../modules/CLAUDE.md) |
| `tests/` | bats, one file per unit | [`tests/CLAUDE.md`](../tests/CLAUDE.md) |

English everywhere: code, comments, commits, docs.

## When something breaks

A crash prints one line — file, line, command, status — whether it happened in
`dot` or inside a module hook run as its own process:

```
  ✗ modules/macos-defaults/apply.sh:24: defaults write com.apple.dock autohide -bool true (exit 1)
```

When one line is not enough, hooks are ordinary scripts:

```sh
bash -x modules/git/apply.sh
```

Every run of `apply`, `add` and `remove` also leaves a transcript under
`~/.local/state/dotfiles/logs/`, and says where at the end.

## Bash 5

macOS still ships 3.2.57 from 2007 as `/bin/bash` and never updates it, so
`install.sh` runs `brew install bash` before anything else in the repo starts,
`core/Brewfile` keeps it managed, `bin/dot` and `uninstall.sh` re-exec
themselves into it, and `lib/dot.sh` refuses outright. Five places, held
together by `contract.bats`.

One Homebrew package in exchange for associative arrays, `mapfile`, and — the
reason it was worth doing — correct line numbers in the crash report above.
Bash 3.2 names a function's *definition* line rather than the failing one.
