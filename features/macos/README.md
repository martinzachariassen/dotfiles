# macOS system defaults

Every `defaults write`, plus Touch ID for sudo. Not run by an apply unless the
module is on; always runnable by hand.

Gated by the `macosDefaults` module.

## Verbs

- `chez macos` — (Re-)apply macOS system defaults on their own.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `scripts/bin/macos-defaults.sh`
- `core/sudo.sh`
- `core/tty.sh`
- `src/.chezmoiscripts/run_before_00-sudo-cache.sh.tmpl`
- `src/.chezmoiscripts/run_onchange_after_04-macos-defaults.sh.tmpl`
- `tests/macos-defaults.bats`
- `tests/sudo-lib.bats`
- `tests/sudo-prompts.bats`
- `docs/macos.md`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
