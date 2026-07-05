# Repository instructions for GitHub Copilot

A personal, chezmoi-managed macOS (Apple Silicon) dotfiles repo. The rules that
matter most when proposing changes here:

## Layout — the `src/` split

- Managed content lives under `src/` — chezmoi's source dir (set via
  `.chezmoiroot`, one line: `src`). Everything at the repo **root** is tooling
  chezmoi never renders: `scripts/` (+ `scripts/lib/`), `packages/` (Brewfiles +
  editor lists), `tests/`, `docs/`, `install.sh`, `.github/`.
- Edit source files here, never the rendered copies in `$HOME` — `chezmoi apply`
  overwrites local drift (`apply.force = true`). To capture a live edit back into
  source, use `chezmoi re-add ~/.X`.

## chezmoi conventions

- Preserve the special prefixes/suffixes: `dot_*`, `private_dot_*`, `remove_*`,
  `run_*` (hook ordering + re-run behavior), and `.tmpl` (Go templates) all
  change how a file is deployed.
- Hooks live in `src/.chezmoiscripts/`; the real logic belongs in plain bash
  under `scripts/lib/`. Because the hooks sit under `src/`,
  `{{ .chezmoi.sourceDir }}` is `…/dotfiles/src` — reach root-level tooling via
  `{{ .chezmoi.workingTree }}` (the git working tree = repo root).

## Shell & runtimes

- Keep shell config plain zsh (XDG layout, `ZDOTDIR=~/.config/zsh`) — no
  oh-my-zsh/prezto/zinit, and no language-runtime managers: runtimes are mise's
  job, global CLIs come from Homebrew.
- Guard shell integrations so a fresh machine starts cleanly before every
  package is installed.

## Quality gates

CI (`.github/workflows/ci.yml`) enforces these, and the pre-commit hooks
(`.pre-commit-config.yaml`) run them locally before a commit lands:

- Shell: `shellcheck --severity=error`, `shfmt -i 4 -ci`, and `bash -n` / `zsh -n`.
- Spelling: `typos` (allowlist + exclusions in `.typos.toml`).
- Config validity: every JSON/JSONC/TOML output parses (`scripts/lint-config.sh`).
- Render: `chezmoi apply --dry-run` across the profile/features matrix.
- Conventional Commits for every commit **and** PR title (subject ≤ 72 chars).
- Never commit secrets, tokens, private keys, credentials, or signing material —
  use placeholders or a secret-manager reference.
