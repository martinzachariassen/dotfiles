# Untracked dotfiles

The file analogue of `mirror`: reconcile untracked `~/.*` and `~/.config/*`
against what chezmoi manages, keeping anything whose owning tool is still here.

## Verbs

- `chez clean` — Remove untracked top-level ~/.* entries, confirming each.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `scripts/bin/clean.sh`
- `src/.chezmoidata/cleanup.toml`
- `tests/chezclean.bats`
- `tests/cleanup-mirror.bats`
- `docs/lifecycle.md`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
