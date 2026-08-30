# The nightly distiller

Turns past Claude sessions into the MAIN.md every future session loads. Two
destinations, a corpus with its own identity, and no human-facing output.

Gated by the `claudeDistiller` module.

## Verbs

- `chez distill` — Distil Claude conversations into the MAIN.md Claude loads.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `scripts/bin/distill.sh`
- `scripts/lib/distill.sh`
- `src/.chezmoidata/distill.toml`
- `src/dot_config/claude/skills/distill/SKILL.md`
- `src/Library/LaunchAgents/no.mlz.chezdistill.nightly.plist.tmpl`
- `src/.chezmoiscripts/run_onchange_after_06-distill.sh.tmpl`
- `tests/distill.bats`
- `docs/distill.md`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
