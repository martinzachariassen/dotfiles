# Dotfiles repo instructions

chezmoi-managed macOS dotfiles. Stack: plain zsh, mise, Brewfile,
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
- `brewfiles/Brewfile.{mac-apps,personal,work}` — layered in by the
  brew-bundle script based on `chezmoi.toml` `profile` and the `macApps`
  feature flag. `Brewfile.mac-apps` holds GUI apps + AI tooling (Ollama, the
  Claude/Codex/ChatGPT apps).
- Language runtimes (java, node, python) come from `mise` — global defaults in
  `dot_config/mise/config.toml`, per-project versions + env in each project's
  own `mise.toml`. Don't put runtimes in Homebrew.
- No other runtime managers (asdf, nvm, jenv, pyenv, rbenv, Volta, SDKMAN).

## Bootstrap & convergence model

The setup experience is **two verbs sharing one engine** — see `docs/lifecycle.md`
for the full contract. Preserve these invariants when touching `install.sh`, the
`.chezmoiscripts/run_after_*` scripts, `scripts/lib/brew-bundle.sh`, or the
`chez*` functions:

- **Apply always converges real state, never input hashes.** The package scripts
  (`run_after_02-brew-bundle`, `run_after_02b-mise-install`) run on *every* apply
  and install based on what's actually present vs. what the Brewfile declares,
  with a fast presence / `mise ls --missing` short-circuit (presence, not
  freshness — upgrades stay `chezbump`'s job). Never turn these back into
  `run_onchange_*` — that reintroduces the drift gap that `chezfix` used to paper
  over.
- **Two everyday verbs only:** `chezup` (converge existing) and `install.sh`
  (bootstrap new), plus `chezdoctor` for health. New capability folds into those
  or an advanced helper (`chez`, `chezreinit`, `chezbump`, `chezaudit`) — don't add
  a fourth daily command.
- **One engine, one look.** Package installs go through `scripts/lib/brew-bundle.sh`;
  terminal color/glyphs through `scripts/lib/ui.sh`. Don't fork a second install
  loop or color scheme.
- **Continue-on-error + idempotent.** A single failing cask must not abort the
  apply; re-running heals.

## Shell and terminal

- Plain zsh — no oh-my-zsh, prezto, zinit, or other framework.
- Guard integrations with `command -v` / file checks so a fresh machine boots
  before every package is installed. Source `zsh-syntax-highlighting` last.
- Preferred tools: Ghostty, Zellij, Starship, fzf, zoxide, Carapace, eza, bat,
  fd, ripgrep, mise.

## install.sh wizard

- `install.sh` is the fragile pre-bootstrap script (runs before chezmoi/brew/mise
  exist). Before changing it or any `prompt_*` / TTY code, read `docs/wizard.md`.
- Reuse the `prompt_*` helpers; never hand-roll TTY input handling around bash
  `read -n` (it ignores your `stty` and hangs). Empty input must re-ask, never
  hard-abort. Every prompt needs a non-tty / `YES=1` default.
- Validate before committing: `bash -n install.sh`, `shellcheck`, then the pty
  drive `python3 tests/drive-wizard.py clean` and `… stray` (must not hang).

## Secrets

Never print, move, transform, commit, or document real tokens, keys, cloud
credentials, signing material, 1Password data, `.env` values, or auth files.
Use placeholders, `.env.example`, or secret-manager refs.

## Verification

- zsh changes: render the template, run `zsh -n` on the result.
- Brewfile changes: `brew bundle check --file=<path>` when practical (newly
  added formulae reporting as missing pre-install is expected).
- Convergence/engine changes (`scripts/lib/brew-bundle.sh`, `run_after_02*`):
  `shellcheck` the lib, render the templates with `chezmoi execute-template` and
  `shellcheck` the output, and run `bats tests/` (covers the extracted helpers).
  See `docs/lifecycle.md`.
- `install.sh` / prompt changes: `bash -n install.sh` + `shellcheck`, then
  `python3 tests/drive-wizard.py clean` and `… stray`. See `docs/wizard.md`.
- Docs-only: skip.
