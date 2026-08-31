# Setup wizard and saved answers

Four questions on a fresh Mac — name, email, git signing and optional modules —
and the way to change any of them later.

## Verbs

- `chez setup` — Fill in newly added setup keys; keeps existing answers.
  `--reset`/`-r` sets the machine up as new.

## Why it is plain text, not chezmoi's TUI

`install.sh` runs under `curl | bash`, where stdin is the script itself.
chezmoi's interactive prompt cannot read a terminal in that situation, so a
fresh-Mac install would hang on the first question. `cli.sh` reads `/dev/tty`
directly and falls back to a pure-bash picker when `gum` is not installed —
which it never is, on the machine that needs this most.

It ends in `exec chezmoi init --apply`, so nothing runs after it.

## The prompt messages are an API

chezmoi keys `--promptString` and `--promptChoice` on the prompt's **message
text**, not its data key. So the strings in
[`src/.chezmoi.toml.tmpl`](../../src/.chezmoi.toml.tmpl) are load-bearing:
`core/prompt-meta.sh` scrapes them back out of the template so that `cli.sh` and
`features/sign/cli.sh` never hardcode them.

Change a message and the wizard silently falls through to chezmoi's raw TUI —
which, per the above, cannot run under `curl | bash`. Messages also cannot
contain a comma, because chezmoi splits those flags on commas.

## What `--reset` actually resets

It clears chezmoi's run-once state so every `run_once_` hook fires again, then
re-asks the full wizard, overriding saved answers. It never uninstalls anything
and never deletes files.

The wizard's existence is checked **before** the state reset, not after. The
reset is the destructive half: failing between it and the wizard would leave a
machine with every hook pending and no way to answer the questions that decide
what those hooks do. The zsh version got this right by accident, because
`_chez_run`'s self-heal ran ahead of the reset; here it is an explicit guard,
pinned by a test.

## Gotchas

The module catalog is read twice from two places, and it has to be. `cli.sh`
awks `[moduleCatalog]` straight out of `modules.toml` because it runs *before*
chezmoi is initialised and `chezmoi data` would have nothing to say.
`.chezmoi.toml.tmpl` restates the same list because a config template renders
before `.chezmoidata` loads. `tests/data-model.bats` holds the two in agreement.
