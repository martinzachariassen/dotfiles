# Repository instructions for GitHub Copilot

Full guidance lives in [`CLAUDE.md`](../CLAUDE.md). The rules that matter most
here:

- This is a chezmoi-managed dotfiles repo. Managed content lives under `src/`
  (chezmoi's source dir, via `.chezmoiroot`); repo tooling (`scripts/`,
  `packages/`, `tests/`, `docs/`) sits at the root. Edit source files here, not
  the rendered files in `$HOME` (an apply overwrites local drift).
- Preserve chezmoi naming and template conventions: `dot_*`, `private_dot_*`,
  `remove_*`, and `.tmpl` files have special meaning.
- Hooks live in `src/.chezmoiscripts/` (`run_*` prefix sets order + re-run
  behavior); the real logic belongs in plain bash under `scripts/lib/`, which
  hooks reach via `{{ .chezmoi.workingTree }}` (the repo root, since the hooks
  themselves are under `src/`).
- Keep shell configuration plain zsh — no oh-my-zsh, prezto, zinit, or language
  runtime managers. Language runtimes are mise's job.
- Guard shell integrations so a fresh machine starts cleanly before every package
  is installed.
- Use Conventional Commits for commit and PR titles (subject ≤ 72 chars).
- Never commit secrets, tokens, private keys, credentials, or signing material.
