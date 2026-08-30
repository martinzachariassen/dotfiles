# Language runtimes (mise)

mise owns every language runtime; Homebrew owns global CLIs. The shims on PATH
in zprofile are what make GUI-launched editors find the right JDK.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `src/dot_config/mise/config.toml.tmpl`
- `src/.chezmoiscripts/run_after_02b-mise-install.sh.tmpl`
- `src/dot_config/zsh/dot_zprofile`
- `tests/mise-config.bats`
- `docs/shell.md (mise section)`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
