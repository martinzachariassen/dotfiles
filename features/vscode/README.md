# VS Code

The app comes from the core Brewfile. Its settings, keybindings and extension
set are managed here, and the extension set is *mirrored* rather than merely
installed: anything the manifest does not list is uninstalled.

## How the mirror works

`extensions.txt` is the single source of truth. On every apply where it or the
engine changes, `run_onchange_after_03-vscode.sh.tmpl` installs every ID it
lists and removes every installed extension it does not. That is deliberate — a
one-way "install these" set drifts the moment you try an extension and forget
it, and the whole point of a managed machine is that a fresh one looks like this
one.

The template is thin on purpose. It resolves the three things only a render can
know — whether this is macOS, and which module-gated extensions to exclude — and
execs `hook.sh` with the exclusions as arguments. Keeping the guards in the
template is what lets `tests/chezmoi-scripts.bats` render every hook on Linux and
prove it exits before touching a macOS command; move a guard into `hook.sh` and
that test passes while actually running bash on the CI runner.

The template hashes **both** `hook.sh` and `extensions.txt`. Hashing only itself
would freeze the engine: chezmoi would keep matching the recorded hash, and the
hook would never run again — no error, no output, extensions silently drifting.
`tests/chezmoi-scripts.bats` enforces the pair for every delegating hook.

`lib.sh` holds the pure set logic — read the manifest, diff it against what is
installed — so it can be unit-tested without VS Code present. `chez doctor`
reports drift in both directions read-only, reading the same manifest through the
same functions, so the report and the apply cannot disagree.

## Module gating

Two groups are excluded from install *and* prune when their module is off: the
Norwegian dictionary under `locale`, and the Swift, SweetPad and LLDB extensions
under `appleDev`. Excluding from both directions is what keeps it consistent —
gate only the install and the prune would immediately uninstall what it just
skipped.

## Gotchas

Some extension packs refuse to uninstall through the CLI when another extension
depends on them. The engine falls back to removing the directory and pruning the
entry from `extensions.json`, which is why `python3` appears in a shell script.

Several extensions are backed by CLIs from the Brewfile — hadolint, shellcheck,
shfmt — so they use the pinned binary rather than downloading their own.

The settings live in `src/`, not here, because chezmoi deploys them to
`~/Library/Application Support/Code/User/`. Only the tooling moved.
