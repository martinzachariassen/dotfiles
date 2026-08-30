# VS Code

Managed settings and keybindings, plus the extension manifest the apply hook
mirrors exactly — anything unlisted is uninstalled.

## Where its code lives today

This feature has not been moved yet. Until it is, these are its parts:

- `scripts/lib/vscode.sh`
- `packages/vscode-extensions.txt`
- `src/Library/Application Support/Code/User/settings.json.tmpl`
- `src/Library/Application Support/Code/User/keybindings.json`
- `src/.chezmoiscripts/run_onchange_after_03-vscode.sh.tmpl`
- `tests/vscode.bats`
- `tests/vscode-extensions.bats`
- `tests/vscode-vim.bats`
- `docs/editors.md`

Moving them here — code, tests and this document — is what turns this stub into
the dossier. See [docs/architecture.md](../../docs/architecture.md).
