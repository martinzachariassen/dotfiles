# chezmoi source ↔ home folder mapping

Reference table showing exactly what each file in the repo does.

## Files chezmoi WRITES to `$HOME`

| Source (in repo) | Destination (in `$HOME`) | Notes |
|---|---|---|
| `dot_zshenv` | `~/.zshenv` | Tiny stub, sets ZDOTDIR + XDG vars + tool env vars. Only file that MUST stay in `$HOME`. |
| `dot_config/zsh/dot_zshrc` | `~/.config/zsh/.zshrc` | Interactive shell config (aliases, completions, claude wrapper). Found via ZDOTDIR. |
| `dot_config/zsh/dot_zprofile` | `~/.config/zsh/.zprofile` | Login shell init (brew shellenv). |
| `dot_config/git/config.tmpl` | `~/.config/git/config` | Templated with name/email/signing key. Git auto-detects this XDG path. |
| `dot_config/git/ignore` | `~/.config/git/ignore` | Global gitignore. |
| `dot_config/mise/config.toml` | `~/.config/mise/config.toml` | mise toolchain definitions. |
| `dot_config/claude/personal/settings.json` | `~/.config/claude/personal/settings.json` | Personal Claude profile (CLAUDE_CONFIG_DIR points here). |
| `dot_docker/config.json` | `~/.docker/config.json` | Docker CLI config. Stays at `~/.docker/` because Docker Desktop hardcodes the path. |
| `dot_docker/daemon.json` | `~/.docker/daemon.json` | Docker daemon config. |
| `dot_config/ghostty/config` | `~/.config/ghostty/config` | Ghostty terminal config. Catppuccin Frappé theme is built into Ghostty, no theme file needed. |
| `dot_config/zellij/config.kdl` | `~/.config/zellij/config.kdl` | Zellij multiplexer config. Catppuccin Frappé theme ships with Zellij ≥0.40. |
| `dot_config/starship.toml` | `~/.config/starship.toml` | Starship prompt config — backend-dev focused, Catppuccin Frappé palette. |
| `dot_config/nvim/init.lua` | `~/.config/nvim/init.lua` | Neovim entrypoint. One-liner: `require("config.lazy")`. |
| `dot_config/nvim/lua/config/lazy.lua` | `~/.config/nvim/lua/config/lazy.lua` | LazyVim bootstrap. Auto-clones lazy.nvim on first launch. Backend-dev language extras (Java/Python/TypeScript/JSON/YAML/Docker/etc.) ship commented-out for opt-in. |
| `dot_config/nvim/lua/plugins/colorscheme.lua` | `~/.config/nvim/lua/plugins/colorscheme.lua` | Catppuccin Frappé colorscheme override for LazyVim. |
| `private_dot_ssh/config` | `~/.ssh/config` | Mode 0600 enforced via `private_` prefix. SSH hardcodes `~/.ssh/`. |
| `Library/Application Support/Code/User/settings.json` | `~/Library/Application Support/Code/User/settings.json` | VS Code user settings (macOS-native location). |

## Files chezmoi REMOVES from `$HOME` (the `remove_` markers)

| Source marker | Removes | Why |
|---|---|---|
| `remove_dot_gitconfig` | `~/.gitconfig` | Git checks `~/.gitconfig` before `~/.config/git/config`, so a legacy file there silently shadows the XDG-managed config. Active protection. |
| `remove_dot_zshrc` | `~/.zshrc` | Real zshrc is at `~/.config/zsh/.zshrc` via `ZDOTDIR`. Legacy file would shadow it. |
| `remove_dot_zprofile` | `~/.zprofile` | Real zprofile is at `~/.config/zsh/.zprofile`. Same reason. |

**Note:** there is *no* `remove_dot_zsh_history` marker. We deliberately don't manage the legacy `~/.zsh_history` or `~/.config/zsh/.zsh_history` files because chezmoi tries to remove them, the live shell (with `SHARE_HISTORY` enabled) recreates them after every command, and the result is an endless "target has changed" prompt every time you run `chezmoi apply`. The new HISTFILE is at `~/.local/state/zsh/history` per `~/.zshenv` + `~/.config/zsh/.zshrc`; any old `.zsh_history` files on disk are inert and you can delete them by hand if you care: `rm -f ~/.zsh_history ~/.config/zsh/.zsh_history`.

## Files chezmoi IGNORES (don't sync to `$HOME`)

Listed in `.chezmoiignore`:

`README.md`, `WORK-SETUP.md`, `MAPPING.md`, `LICENSE`, `install.sh`, `Brewfile`, `macos-defaults.sh`, `.editorconfig`, `.gitattributes`, `.github/`, `.gitignore`, `.DS_Store`

These are repo metadata, install scripts, or holding-pen files for things we removed.

## chezmoi infrastructure (not files in `$HOME`, but used by chezmoi itself)

| File | Role |
|---|---|
| `.chezmoi.toml.tmpl` | Init prompts. Renders to `~/.config/chezmoi/chezmoi.toml` on `chezmoi init`. |
| `.chezmoidata/packages.toml` | Data file (vscode extension list) available to all templates. |
| `.chezmoiignore` | List of patterns to skip. |
| `.chezmoiscripts/run_once_before_01-install-homebrew.sh.tmpl` | Runs once before any apply. macOS-only via template guard. |
| `.chezmoiscripts/run_onchange_after_02-brew-bundle.sh.tmpl` | Runs after apply when Brewfile content hash changes. macOS-only. |
| `.chezmoiscripts/run_onchange_after_03-vscode-extensions.sh.tmpl` | Runs after apply when extension list changes. macOS-only. |
| `.chezmoiscripts/run_once_after_04-macos-defaults.sh.tmpl` | Runs `macos-defaults.sh` exactly **once per machine** (`run_once_*`, not `run_onchange_*`). chezmoi records the run and never repeats it, even if you edit the script. To re-apply edits, run the `macos-defaults` zsh alias manually. The wrapper reopens stdin from `/dev/tty` so sudo's password prompt works through chezmoi's non-interactive script context. |
| `macos-defaults.sh` (root) | The actual defaults script. Invoked by chezmoi on first apply (via the wrapper above) and re-runnable on demand via the `macos-defaults` zsh alias. |

---

## What's in `$HOME` AFTER everything applies

These are the dotfiles/dirs that will remain — and the reason each one can't go elsewhere:

| Path | Why it can't move |
|---|---|
| `~/.zshenv` | zsh reads this BEFORE any environment variables are set. Hardcoded. |
| `~/.config/`, `~/.local/`, `~/.cache/` | These ARE the XDG dirs. They're where everything moved TO. |
| `~/.ssh/` | OpenSSH hardcodes `~/.ssh/` for keys, known_hosts, agent socket. Cannot move. |
| `~/.docker/` | Docker Desktop GUI writes here regardless of `DOCKER_CONFIG`. Moving the CLI config would create drift. |
| `~/.vscode/`, `~/.vscode-shared/` | VS Code on macOS hardcodes `~/.vscode/` for extensions and CLI binary. |
| `~/.claude/` | Work Claude Code, installed by storecode. Hooks reference absolute `/Users/martin/.storecode/...` paths. Touching it breaks work. |
| `~/.storecode/`, `~/.rampart/`, `~/.copilot/` | Work tooling installed by your employer. Hardcoded. |
| `~/.m2/` | Maven 3.x doesn't have a clean XDG override. Maven 4 does (`MAVEN_USER_CONFIG_HOME`) — revisit when you move to mvn 4. |
| `~/.claude.json` | Claude Code session state, hardcoded path inside the binary. |
| `~/.CFUserTextEncoding`, `~/.Trash/` | macOS system files. |
| `Applications/`, `Desktop/`, `Documents/`, `Downloads/`, `Library/`, `Movies/`, `Music/`, `Pictures/`, `Public/`, `Dev/` | User folders, not dotfiles. |

That's the floor. ~11 dotfile entries instead of the 14 you started with, and each remaining one has a concrete technical reason.
