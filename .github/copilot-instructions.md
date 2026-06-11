# Repository instructions for GitHub Copilot

Full guidance lives in [`CLAUDE.md`](../CLAUDE.md). The rules that matter most
here:

- This is a chezmoi-managed dotfiles repo. Edit source files here, not the
  rendered files in `$HOME` (an apply overwrites local drift).
- Preserve chezmoi naming and template conventions: `dot_*`, `private_dot_*`,
  `remove_*`, and `.tmpl` files have special meaning.
- Hooks live in `.chezmoiscripts/` (`run_*` prefix sets order + re-run behavior);
  the real logic belongs in plain bash under `scripts/lib/`.
- Keep shell configuration plain zsh — no oh-my-zsh, prezto, zinit, or language
  runtime managers. Language runtimes are mise's job.
- Guard shell integrations so a fresh machine starts cleanly before every package
  is installed.
- Use Conventional Commits for commit and PR titles (subject ≤ 72 chars).
- Never commit secrets, tokens, private keys, credentials, or signing material.
