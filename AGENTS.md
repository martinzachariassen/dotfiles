# Dotfiles repo instructions

chezmoi-managed macOS dotfiles. Stack: plain zsh, devbox + direnv, Brewfile,
Ghostty + Zellij, Starship, Claude Code, Codex. Prefer small, reviewable
edits that preserve existing patterns.

## Chezmoi

- Source prefixes: `dot_*` → `~/.X`, `private_dot_*` → mode-0600. `.tmpl`
  files are Go templates — preserve conditionals and `{{ .data }}` refs.
- Edit source files in this repo, never the rendered files in `$HOME`.
- When adding, removing, or relocating managed files, update `docs/mapping.md`.
- Repo metadata (docs, scripts, Brewfiles, `.github/`, `AGENTS.md`,
  `CLAUDE.md`) stays repo-local via `.chezmoiignore`.

## Brewfiles

- `Brewfile` — core CLIs, always installed.
- `brewfiles/Brewfile.{ai,mac-apps,personal,work}` — layered in by the
  brew-bundle script based on `chezmoi.toml` `profile` and
  `features.{ai,macApps}` flags.
- Per-project runtimes and CLIs live in that project's `devbox.json`.
- No runtime managers (mise, asdf, nvm, jenv, pyenv, rbenv, Volta, SDKMAN).

## Shell and terminal

- Plain zsh — no oh-my-zsh, prezto, zinit, or other framework.
- Guard integrations with `command -v` / file checks so a fresh machine boots
  before every package is installed. Source `zsh-syntax-highlighting` last.
- Preferred tools: Ghostty, Zellij, Starship, fzf, zoxide, Carapace, eza, bat,
  fd, ripgrep, direnv, devbox.

## Secrets

Never print, move, transform, commit, or document real tokens, keys, cloud
credentials, signing material, 1Password data, `.env` values, or auth files.
Use placeholders, `.env.example`, or secret-manager refs.

## Git

- Never add a `Co-Authored-By: Claude` trailer (or any Claude/AI co-author
  attribution) to commit messages.

## Verification

- zsh changes: render the template, run `zsh -n` on the result.
- Brewfile changes: `brew bundle check --file=<path>` when practical (newly
  added formulae reporting as missing pre-install is expected).
- Docs-only: skip.
