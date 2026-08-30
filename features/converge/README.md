# Converge this Mac to the repo

The everyday path. `chez up` pulls, previews what would change, and applies;
`chez apply` does the apply without the pull; `chez status` explains the drift
without touching anything; `chez reconcile` chains install-then-remove.

## Verbs

- `chez up` — Pull → preview → apply. The command you run most.
- `chez apply` — Apply without pulling. Flags drift; never uninstalls.
- `chez status` — Explain pending file and package drift in plain words.
- `chez reconcile` — Full package reconcile: install then remove.
- `chez cd` — cd into the source repo. Stays a shell function; a script cannot
  change its caller's directory.

## Why apply never removes

An apply adds and updates. It renders managed files, runs `brew bundle`, installs
missing runtimes — and stops there. Nothing it does deletes a package or a
dotfile, so a routine converge can never surprise you by taking something away.

`apply.sh` still *reports* untracked packages, because silence would be worse:
you would not know the machine had drifted. It points at `chezmirror`, which is
the verb that removes, and which confirms every package separately. Files are
`chezclean`. Both are things you run on purpose.

That asymmetry is the whole design. `reconcile.sh` exists for when you want both
directions in one step, and it is still two explicit passes rather than a single
silent one.

## Drift has two halves

`status.sh` reports both, because they fail differently. **File drift** is the
repo and `$HOME` disagreeing — either the repo has changes to push out, or you
edited a managed file in place and the next apply will overwrite it. **Package
drift** is something installed that no active Brewfile declares.

The status codes come straight from `chezmoi status`, so the left column is your
local edits and the right is what an apply would write. `status.sh` translates
that into words, and `chez status -v` or a path argument drops through to raw
`chezmoi diff` when you want the real thing.

## Gotchas

`reconcile.sh` invokes `up.sh` and `../brew/mirror.sh` **by path**. They were
shell functions calling shell functions when all four lived in the zshrc; as
scripts they have to be executed, not called.

The removal set comes from `../brew/lib/removals.sh` — the same resolver
`chezmirror` acts on and `chezdoctor` reports against, so "untracked" cannot mean
three different things.
