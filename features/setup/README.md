# Setup wizard and saved answers

The four questions, the module catalog, and the flag mapping that lets
`chezmoi init` run them non-interactively.

## Verbs

- `chez setup` — Fill in newly-added setup keys; keeps existing answers.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `scripts/bin/wizard.sh`
- `core/prompt-meta.sh`
- `core/modules.sh`
- `src/.chezmoi.toml.tmpl`
- `src/.chezmoidata/modules.toml`
- `src/dot_config/zsh/dot_zshrc.tmpl (chezsetup — inline zsh)`
- `tests/wizard.bats`
- `tests/chezsetup.bats`
- `tests/setup-ux.bats`
- `tests/data-model.bats`
- `docs/install.md`
- `docs/packages.md`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
