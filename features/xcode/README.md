# Xcode and iOS

Everything an apply deliberately cannot do: Xcode.app itself, the selected
developer dir, the licence, first-launch, and a simulator runtime.

Gated by the `appleDev` module.

## Verbs

- `chez xcode` — Install Xcode + iOS simulator runtime (Apple ID, ~40 GB).

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `scripts/bin/xcode.sh`
- `scripts/lib/xcode.sh`
- `scripts/lib/xcodes.sh`
- `src/.chezmoidata/xcodes.toml`
- `packages/Brewfile.apple-dev`
- `src/dot_swiftformat`
- `src/dot_config/swiftlint/config.yml`
- `tests/chezxcode.bats`
- `tests/xcode-lib.bats`
- `tests/xcodes-lib.bats`
- `tests/apple-dev.bats`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
