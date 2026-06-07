# Dotfiles repo instructions

chezmoi-managed macOS dotfiles. Plain zsh + mise + Brewfile. Small, reviewable
edits that preserve existing patterns.

## Conventions

- Edit sources in this repo, never the rendered files in `$HOME`.
- Source prefixes: `dot_*` → `~/.X`, `private_dot_*` → mode-0600, `.tmpl` are
  Go templates.
- Brewfiles layer by `chezmoi.toml` profile: core `Brewfile` plus
  `brewfiles/Brewfile.{mac-apps,personal,work}`. Language runtimes come from
  mise, not Homebrew.

## Load-bearing invariants

- **Apply always converges real state.** Package scripts are `run_after_*`
  (every apply, presence-based short-circuit) — never `run_onchange_*`.
- **Two everyday verbs:** `chezup` (converge) and `install.sh` (bootstrap),
  plus `chezdoctor`. Don't add a fourth.
- **One engine, one look.** Package installs go through
  `scripts/lib/brew-bundle.sh`; terminal styling through `scripts/lib/ui.sh`.
- **`install.sh` is pre-bootstrap and fragile** — runs before chezmoi/brew/
  mise exist. Use the `prompt_*` helpers, never raw `read -n`.

## Verification

Match the check to the change: `zsh -n`, `shellcheck`, `bats tests/`,
`python3 tests/drive-wizard.py clean stray`.
