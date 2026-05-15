# Repository instructions for GitHub Copilot

Follow the repo-local instructions in [`AGENTS.md`](../AGENTS.md). The most
important rules for this repository are:

- This is a chezmoi-managed dotfiles repo. Edit source files here, not rendered
  files in `$HOME`.
- Preserve chezmoi naming and template conventions: `dot_*`, `private_dot_*`,
  `remove_*`, and `.tmpl` files have special meaning.
- Update `docs/mapping.md` when adding, removing, or relocating managed files.
- Keep shell configuration plain zsh. Do not introduce oh-my-zsh, prezto, zinit,
  or language runtime managers.
- Guard shell integrations so a fresh machine still starts cleanly before every
  package is installed.
- Never expose or commit secrets, tokens, private keys, cloud credentials,
  signing material, auth files, or real `.env` values.

