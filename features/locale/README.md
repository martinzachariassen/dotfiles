# Spelling and locale

The shared cSpell dictionary and the Norwegian spell-check layer. The personal
dictionary is a symlink into this repo — the one managed path a file move can
break.

Gated by the `locale` module.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `packages/cspell-words.txt`
- `src/dot_config/cspell/symlink_personal.txt.tmpl`
- `src/Library/Application Support/Code/User/settings.json.tmpl (cSpell block)`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
