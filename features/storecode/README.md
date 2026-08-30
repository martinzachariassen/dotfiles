# storecode (work profile)

The work-only exception: installed by its own hook from an installer set in
data, never from a Brewfile, and permanently on the cleanup keep-list.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `src/.chezmoidata/storecode.toml`
- `src/.chezmoiscripts/run_onchange_after_05-storecode.sh.tmpl`
- `tests/cleanup-mirror.bats (storecode half)`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
