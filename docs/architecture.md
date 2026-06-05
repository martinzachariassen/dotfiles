# Architecture

Three classes of files in this repo, plus chezmoi's own infrastructure.

**1. Files chezmoi writes to `$HOME`** — anything prefixed `dot_` (becomes `.X`), `private_dot_` (also enforces mode 0600). Templates end in `.tmpl` and get rendered with chezmoi's data at apply time. So `dot_config/git/config.tmpl` becomes `~/.config/git/config` with your name/email/signing key substituted in. `dot_config/zsh/dot_zshrc.tmpl` includes profile-conditional blocks rendered only when `{{ .profile }}` matches.

**2. Files chezmoi removes from `$HOME`** — `remove_*` markers are empty sentinels whose filename encodes a delete instruction. `remove_dot_gitconfig` ensures `~/.gitconfig` doesn't exist (because git checks `~/.gitconfig` *before* `~/.config/git/config` and would silently shadow our XDG-managed config). `remove_dot_zshrc` and `remove_dot_zprofile` defend the `ZDOTDIR`-based zsh layout. `remove_dot_bash_profile`, `remove_dot_bashrc`, and `remove_dot_profile` keep old bash/POSIX login hooks from accumulating stale bootstrap code in `$HOME`.

**3. Files chezmoi ignores entirely** — listed in `.chezmoiignore`. Repo documentation (`README.md`, `docs/`, `LICENSE`), the public installer (`install.sh`), helper scripts (`scripts/`), the Homebrew bundle files (`Brewfile`, `brewfiles/`), CI (`.github/`), formatters (`.editorconfig`, `.gitattributes`), examples (`examples/`), git's own files, and the repo-local AI instructions (`AGENTS.md`, `CLAUDE.md`). The AI files are explicitly ignored because `CLAUDE.md` rendered into `$HOME` would shadow the user-level `~/.config/claude/CLAUDE.md`.

**chezmoi infrastructure**:

- `.chezmoi.toml.tmpl` — init prompts. Renders to `~/.config/chezmoi/chezmoi.toml` on `chezmoi init`.
- `.chezmoiscripts/` — auto-run hooks. Five user-visible steps per apply, in order:

  | # | Script | Phase | Runs when | What it does |
  |---|---|---|---|---|
  | 1 | `run_before_00-sudo-cache` | before, every apply | always | Pre-authenticates sudo on a clean terminal + background keeper refreshing every 50s. Silent no-op when sudo is already cached or there's no TTY. |
  | — | `run_once_before_01-install-homebrew` | before, once | first apply only | Installs Homebrew if missing. Silent on every subsequent apply. |
  | 3 | `run_after_02-brew-bundle` | after, **every apply** | always (fast short-circuit when clean) | Reconciles real installed state against the active Brewfile modules (core + enabled workstation extras + profile extras). A fast presence short-circuit (is each declared formula/cask/tap installed?) makes a clean machine a quick no-op; only genuinely-missing items trigger the per-item install (freshness is `chezbump`'s job, not the apply's). Continue-on-error: one bad cask never aborts the apply. Engine lives in `scripts/lib/brew-bundle.sh`. `exec </dev/tty` so sudo-requiring casks (docker-desktop, 1password) can read the password; heartbeat every 30s during silent stretches. |
  | 2b | `run_after_02b-mise-install` | after, **every apply** | always (fast short-circuit when clean) | Runs after brew-bundle (so `mise` is on PATH) and `mise install`s the global runtimes pinned in `~/.config/mise/config.toml` so the first interactive shell just works. `mise ls --missing` short-circuits when nothing's missing; idempotent. |
  | — | `run_onchange_after_02c-cleanup-deprecated` | after, on manifest change | when inputs change | Removes tooling the repo intentionally dropped, from an explicit manifest (deprecated Homebrew formulae/casks, the old devbox binary, direnv/devbox config dirs). Only touches named items; guarded so it's a no-op on fresh machines. The irreversible `/nix` store is removed only after an interactive y/N. Has its own `◆ Cleanup` banner rather than an `Apply N/5` step. |
  | 4 | `run_onchange_after_03-vscode` | after, on script/extension manifest change | when inputs change | Installs VS Code extensions from `vscode/extensions.txt`, removes deprecated extensions, and refreshes the JetBrains Kotlin VSIX. |
  | 5 | `run_onchange_after_04-macos-defaults` | after, on script change | when `scripts/macos-defaults.sh` changes | Runs `scripts/macos-defaults.sh`. A routine apply that doesn't touch the script is a no-op — re-apply edits via the `macos-defaults` zsh alias. |
  | — | `run_onchange_after_99-completion` | after, every apply | always | Prints the `✓ chezmoi apply complete` banner with the day-to-day reference card. Re-fires because the rendered content embeds `{{ now.Unix }}`. |

  The `Apply N/5` headings you see in output match this numbering, so a wall of brew-bundle output never leaves you wondering what's left.
