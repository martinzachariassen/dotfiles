# Dotfiles repo instructions

This repository is a chezmoi-managed macOS dotfiles repo. Prefer small,
reviewable edits that preserve the existing plain-zsh, devbox, direnv, Brewfile,
Ghostty, Zellij, Starship, Claude Code, and Codex setup.

## Chezmoi conventions

- Source files prefixed `dot_*` map to dotfiles in `$HOME`; for example
  `dot_config/zsh/dot_zshrc.tmpl` renders to `~/.config/zsh/.zshrc`.
- `private_dot_*` files are installed with private permissions. Treat them as
  sensitive by default.
- Files ending in `.tmpl` are Go templates rendered by chezmoi. Preserve
  template conditionals and data references unless the change is explicitly
  about those values.
- Do not edit live files in `$HOME` for managed dotfiles. Edit the source file
  in this repo.
- When adding, removing, or relocating managed files, update `docs/mapping.md`.
- Repo metadata such as docs, examples, scripts, Brewfiles, `.github/`, and this
  `AGENTS.md` should stay ignored by chezmoi via `.chezmoiignore` unless it is
  intentionally meant to be applied into `$HOME`.

## Package and tool ownership

- Add common workstation CLIs to `Brewfile`.
- Add profile-specific apps to `brewfiles/Brewfile.personal` or
  `brewfiles/Brewfile.work`.
- Keep project runtimes and project CLIs in per-project `devbox.json` files, not
  in this repo's global Brewfile.
- Do not introduce runtime managers such as mise, asdf, nvm, jenv, pyenv,
  rbenv, Volta, or SDKMAN.

## Shell and terminal

- Keep zsh configuration plain and readable. Do not add oh-my-zsh, prezto,
  zinit, or another zsh framework.
- Guard shell integrations with `command -v` or file existence checks so a fresh
  machine can open a shell before every package is installed.
- Source `zsh-syntax-highlighting` last.
- Prefer existing tools and aliases: Ghostty, Zellij, Starship, fzf, zoxide,
  Carapace, eza, bat, fd, ripgrep, direnv, and devbox.

## Secrets and safety

- Never print, move, transform, commit, or document real tokens, private keys,
  cloud credentials, signing material, 1Password data, local `.env` values, or
  auth files.
- Use placeholders, `.env.example`, or references to a secret manager instead
  of real values.

## Verification

- For zsh changes, render templates where relevant and run `zsh -n` on the
  rendered file.
- For Brewfile changes, run `brew bundle check --file=...` when practical. It is
  acceptable for the check to report newly added formulae as missing before
  install.
- Keep verification narrow for docs-only changes.

