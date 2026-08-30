# Git commit signing

Setting the signing key on its own, because the key lives in 1Password and
1Password is not installed until after the wizard has already asked for it.

## Verbs

- `chez sign` — Set the git signing key on its own; keeps every other answer.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `scripts/bin/signing.sh`
- `scripts/lib/git-signing.sh`
- `src/dot_config/git/config.tmpl`
- `src/dot_config/git/allowed_signers.tmpl`
- `src/private_dot_ssh/config`
- `tests/chezsign.bats`
- `tests/git-email.bats`
- `docs/commands.md`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
