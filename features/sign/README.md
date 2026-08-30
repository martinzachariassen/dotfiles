# Git commit signing

`chez sign` (today: `chezsign`) sets the commit signing key on its own, keeping
profile, modules and identity exactly as they are.

## Why it exists

A bootstrap chicken-and-egg. The signing key lives in 1Password, and Homebrew
does not install 1Password until *after* the wizard has already asked which key
to use. So a fresh Mac has to defer that one answer, and needs a way to supply it
later without re-running the whole wizard.

It offers the keys the SSH agent is already holding — 1Password's socket first,
then `$SSH_AUTH_SOCK` — so there is nothing to paste. It also accepts a key as an
argument, stripping any trailing agent comment, because `allowed_signers` is
`<email> <key>` per line and the comment would corrupt it.

It finishes by making a real signed commit in a throwaway repo. Setting a key
that turns out not to work is the failure this exists to prevent, and only an
actual signature proves otherwise.

## How it keeps every other answer

Re-running `chezmoi init` would re-ask everything. Instead `cli.sh` reads the
current answers out of `chezmoi data` and replays them as `--promptString` /
`--promptChoice` flags, changing only the key.

Those flags are keyed on the prompt's **message text**, not its data key, so the
messages in `src/.chezmoi.toml.tmpl` are a public API. `core/prompt-meta.sh`
scrapes them back out of the template rather than hardcoding them — change a
message and the wizard silently falls through to chezmoi's raw TUI, which cannot
run under `curl | bash`. Messages also cannot contain a comma, because chezmoi
splits those flags on commas.

## Gotchas

It refuses when `signingMode` is `off`. Turning signing back on is a different
decision, and belongs to `chez setup --reset`.

`lib.sh` holds the 1Password agent probe and the smoke test. The `auth` feature
borrows it rather than keeping a second copy, so a change to how signing is
verified lands in both places at once.
