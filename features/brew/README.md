# Homebrew packages

The Brewfile tiers, the resolver both install and removal read, tap trust, the
progress bar, and the removal-only reconcile.

## Verbs

- `chez bump` — Upgrade deps: brew upgrade + mise upgrade.
- `chez mirror` — Uninstall untracked packages (removal only), confirming each.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `scripts/lib/brewfiles.sh`
- `scripts/lib/homebrew.sh`
- `scripts/lib/brew-progress.sh`
- `packages/Brewfile*`
- `src/.chezmoidata/packages.toml`
- `src/.chezmoiscripts/run_once_before_01-install-homebrew.sh.tmpl`
- `src/.chezmoiscripts/run_after_02-brew-bundle.sh.tmpl`
- `src/dot_config/zsh/dot_zshrc.tmpl (chezmirror, chezbump, _chez_brew_* — inline zsh)`
- `scripts/ci/brew-resolve.sh`
- `scripts/ci/brew-check-modules.sh`
- `tests/chezmirror.bats`
- `tests/brewfiles-lib.bats`
- `tests/homebrew-lib.bats`
- `tests/brew-trust.bats`
- `tests/brew-failure-report.bats`
- `tests/progress.bats`
- `tests/brewfile-contents.bats`
- `docs/packages.md`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
