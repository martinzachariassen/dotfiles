# Converge this Mac to the repo

Pull, preview and apply. The everyday path, plus the read-only drift report
and the both-directions reconcile.

## Verbs

- `chez up` — Pull → preview → apply. The command you run most.
- `chez apply` — Apply without pulling. Flags drift; never uninstalls.
- `chez status` — Explain pending file + package drift in plain words (read-only).
- `chez reconcile` — Full package reconcile: install then remove.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `scripts/bin/chezup.sh`
- `src/dot_config/zsh/dot_zshrc.tmpl (chezapply, chezstatus, chezreconcile, dotfiles — inline zsh)`
- `tests/chezup.bats`
- `tests/chezreconcile.bats`
- `tests/chez-functions.bats`
- `docs/commands.md`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
