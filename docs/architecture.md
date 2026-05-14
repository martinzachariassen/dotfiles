# Architecture

Three classes of files in this repo, plus chezmoi's own infrastructure.

**1. Files chezmoi writes to `$HOME`** — anything prefixed `dot_` (becomes `.X`), `private_dot_` (also enforces mode 0600). Templates end in `.tmpl` and get rendered with chezmoi's data at apply time. So `dot_config/git/config.tmpl` becomes `~/.config/git/config` with your name/email/signing key substituted in. `dot_config/zsh/dot_zshrc.tmpl` includes profile-conditional blocks rendered only when `{{ .profile }}` matches.

**2. Files chezmoi removes from `$HOME`** — `remove_*` markers are empty sentinels whose filename encodes a delete instruction. `remove_dot_gitconfig` ensures `~/.gitconfig` doesn't exist (because git checks `~/.gitconfig` *before* `~/.config/git/config` and would silently shadow our XDG-managed config). `remove_dot_zshrc` and `remove_dot_zprofile` defend the `ZDOTDIR`-based zsh layout. `remove_dot_bash_profile`, `remove_dot_bashrc`, and `remove_dot_profile` keep old bash/POSIX login hooks from accumulating stale bootstrap code in `$HOME`.

**3. Files chezmoi ignores entirely** — listed in `.chezmoiignore`. Repo documentation (`README.md`, `docs/`, `LICENSE`), the public installer (`install.sh`), helper scripts (`scripts/`), the Homebrew bundle files (`Brewfile`, `brewfiles/`), CI (`.github/`), formatters (`.editorconfig`, `.gitattributes`), examples (`examples/`), git's own files.

**chezmoi infrastructure**:

- `.chezmoi.toml.tmpl` — init prompts. Renders to `~/.config/chezmoi/chezmoi.toml` on `chezmoi init`.
- `.chezmoiscripts/` — auto-run hooks. Four user-visible steps per apply, in order:

  | # | Script | Phase | Runs when | What it does |
  |---|---|---|---|---|
  | 1 | `run_before_00-sudo-cache` | before, every apply | always | Pre-authenticates sudo on a clean terminal + background keeper refreshing every 50s. Silent no-op when sudo is already cached or there's no TTY. |
  | — | `run_once_before_01-install-homebrew` | before, once | first apply only | Installs Homebrew if missing. Silent on every subsequent apply. |
  | 2 | `run_onchange_before_01b-install-devbox` | before, on script change | always (idempotent) | Two-part: curl-installs devbox CLI from Jetify if missing, then bootstraps the Nix store at `/nix` via the Determinate Systems installer (`--determinate --no-confirm`). Both halves short-circuit when already present. |
  | 3 | `run_onchange_after_02-brew-bundle` | after, on Brewfile/profile/feature change | always | Layers core Brewfile + enabled workstation extras + your profile's extras. `exec </dev/tty` so sudo-requiring casks (docker-desktop, 1password) can read the password. Heartbeat every 45s during silent stretches. |
  | 4 | `run_once_after_04-macos-defaults` | after, once | first apply only | Runs `scripts/macos-defaults.sh`. Never re-fires automatically — re-apply edits via the `macos-defaults` zsh alias. |
  | — | `run_onchange_after_99-completion` | after, every apply | always | Prints the `✓ chezmoi apply complete` banner with the day-to-day reference card. Re-fires because the rendered content embeds `{{ now.Unix }}`. |

  The "step N/4" prefixes you see in apply output (`[brew-bundle] apply step 3/4 …`) match this numbering, so a wall of brew-bundle output never leaves you wondering what's left.
