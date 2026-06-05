# chezmoi source ↔ home folder mapping

Reference table showing exactly what each file in the repo does.

## Files chezmoi WRITES to `$HOME`

| Source (in repo) | Destination (in `$HOME`) | Notes |
|---|---|---|
| `dot_zshenv` | `~/.zshenv` | Tiny stub, sets ZDOTDIR + XDG vars + tool env vars. Only file that MUST stay in `$HOME`. |
| `dot_config/zsh/dot_zshrc` | `~/.config/zsh/.zshrc` | Interactive shell config (aliases, completions). Found via ZDOTDIR. |
| `dot_config/zsh/dot_zprofile` | `~/.config/zsh/.zprofile` | Login shell init (brew shellenv). |
| `dot_config/git/config.tmpl` | `~/.config/git/config` | Templated with name/email/signing key and SSH signing settings. Git auto-detects this XDG path. |
| `dot_config/git/allowed_signers.tmpl` | `~/.config/git/allowed_signers` | Templated allowed signers file so Git can verify local SSH commit signatures. |
| `dot_config/git/ignore` | `~/.config/git/ignore` | Global gitignore. |
| `dot_config/mise/config.toml` | `~/.config/mise/config.toml` | mise global config — default language runtimes (`java = ["temurin-21", "temurin-25"]`, `node = "lts"`). Per-project versions + env vars live in each project's own `mise.toml` and override these on `cd`. |
| `dot_config/claude/CLAUDE.shared.md.tmpl` | `~/.config/claude/CLAUDE.shared.md` | Shared Claude Code base. Thin wrapper that `includeTemplate`s `.chezmoitemplates/agents/shared.md` (the single source of truth, shared verbatim with Codex). `@import`ed by the rendered `CLAUDE.md`. Always applied. |
| `dot_config/claude/CLAUDE.md.tmpl` | `~/.config/claude/CLAUDE.md` | Active-profile Claude Code memory. Renders by including `.chezmoitemplates/claude/<profile>.md`; its first line is `@~/.config/claude/CLAUDE.shared.md`, so the shared base layers in at memory-load time. `CLAUDE_CONFIG_DIR=~/.config/claude` (set in `.zshenv`) tells Claude Code to read this. |
| `.chezmoitemplates/claude/personal.md` | *(not copied to $HOME)* | Personal-profile body. Pulled into `CLAUDE.md` via `includeTemplate` when `profile = personal`. |
| `.chezmoitemplates/claude/work.md` | *(not copied to $HOME)* | Work-profile body. Pulled into `CLAUDE.md` via `includeTemplate` when `profile = work`. |
| `.chezmoitemplates/agents/shared.md` | *(not copied to $HOME)* | Single source of truth for personal AI defaults (about-me, communication, code style, environment, secrets, commits). `includeTemplate`d into both `CLAUDE.shared.md` and the Codex `AGENTS.md` so they can't drift. |
| `dot_codex/AGENTS.md.tmpl` | `~/.codex/AGENTS.md` | Global Codex instructions auto-loaded into every personal Codex session. `includeTemplate`s the shared base (`.chezmoitemplates/agents/shared.md`), then appends Codex-only operational detail (tool inventory, autonomy, dotfiles-repo notes). Project-specific overrides go in `<project>/AGENTS.md`. |
| `Library/Application Support/Code/User/settings.json.tmpl` | `~/Library/Application Support/Code/User/settings.json` | VS Code user settings. Templated so the Java runtime paths resolve to this machine's mise install dir (`{{ .chezmoi.homeDir }}/.local/share/mise/installs/java/...`). This path is not XDG; VS Code on macOS hardcodes it under `~/Library/Application Support`. |
| `Library/Application Support/Code/User/keybindings.json` | `~/Library/Application Support/Code/User/keybindings.json` | VS Code custom keybindings. Editor-chrome chords (pane/group management, terminal split) that complement the vim leader maps held in `settings.json`. |
| `Library/Application Support/Code/User/snippets/*.json` | `~/Library/Application Support/Code/User/snippets/*.json` | VS Code user snippets (per-language). |
| `dot_docker/config.json` | `~/.docker/config.json` | Docker CLI config. Stays at `~/.docker/` because Docker Desktop hardcodes the path. |
| `dot_docker/daemon.json` | `~/.docker/daemon.json` | Docker daemon config. |
| `dot_config/ghostty/config` | `~/.config/ghostty/config` | Ghostty terminal config. Catppuccin Frappé theme is built into Ghostty, no theme file needed. |
| `dot_config/zellij/config.kdl` | `~/.config/zellij/config.kdl` | Zellij multiplexer config. Catppuccin Frappé theme ships with Zellij ≥0.40. |
| `dot_config/starship.toml` | `~/.config/starship.toml` | Starship prompt config — backend-dev focused, Catppuccin Frappé palette. |
| `dot_config/nvim/init.lua` | `~/.config/nvim/init.lua` | Neovim entrypoint. One-liner: `require("config.lazy")`. |
| `dot_config/nvim/lua/config/lazy.lua` | `~/.config/nvim/lua/config/lazy.lua` | LazyVim bootstrap. Auto-clones lazy.nvim on first launch. Backend-dev language extras (Java/Python/TypeScript/JSON/YAML/Docker/etc.) ship commented-out for opt-in. |
| `dot_config/nvim/lua/plugins/colorscheme.lua` | `~/.config/nvim/lua/plugins/colorscheme.lua` | Catppuccin Frappé colorscheme override for LazyVim. |
| `dot_config/nvim/lazy-lock.json` | `~/.config/nvim/lazy-lock.json` | lazy.nvim lockfile — pins exact plugin commits so installs are reproducible. Bump with `:Lazy update` then `chezmoi add`. See [day-to-day](day-to-day.md) → "Pinning Neovim plugins". |
| `private_dot_ssh/config` | `~/.ssh/config` | Mode 0600 enforced via `private_` prefix. SSH hardcodes `~/.ssh/`. |

## Files chezmoi REMOVES from `$HOME` (the `remove_` markers)

| Source marker | Removes | Why |
|---|---|---|
| `remove_dot_gitconfig` | `~/.gitconfig` | Git checks `~/.gitconfig` before `~/.config/git/config`, so a legacy file there silently shadows the XDG-managed config. Active protection. |
| `remove_dot_zshrc` | `~/.zshrc` | Real zshrc is at `~/.config/zsh/.zshrc` via `ZDOTDIR`. Legacy file would shadow it. |
| `remove_dot_zprofile` | `~/.zprofile` | Real zprofile is at `~/.config/zsh/.zprofile`. Same reason. |
| `remove_dot_bash_profile` | `~/.bash_profile` | Legacy login-shell file. This setup is zsh/XDG-based, so keeping it in `$HOME` creates stale bootstrap hooks. Active protection. |
| `remove_dot_bashrc` | `~/.bashrc` | Legacy interactive bash file. Active protection. |
| `remove_dot_profile` | `~/.profile` | Legacy POSIX login-shell file. Active protection. |
| `remove_dot_continue` | `~/.continue` | Legacy Continue extension config and indexes. Continue is no longer part of the managed VS Code setup. |

**Note:** there is *no* `remove_dot_zsh_history` marker. We deliberately don't manage the legacy `~/.zsh_history` or `~/.config/zsh/.zsh_history` files because chezmoi tries to remove them, the live shell (with `SHARE_HISTORY` enabled) recreates them after every command, and the result is an endless "target has changed" prompt every time you run `chezmoi apply`. The new HISTFILE is at `~/.local/state/zsh/history` per `~/.zshenv` + `~/.config/zsh/.zshrc`; any old `.zsh_history` files on disk are inert and you can delete them by hand if you care: `rm -f ~/.zsh_history ~/.config/zsh/.zsh_history`.

## Files chezmoi IGNORES (don't sync to `$HOME`)

Listed in `.chezmoiignore`:

`README.md`, `AGENTS.md`, `CLAUDE.md`, `docs/`, `LICENSE`, `install.sh`, `scripts/`, `Brewfile`, `Brewfile.lock.json`, `brewfiles/`, `vscode/`, `.editorconfig`, `.gitattributes`, `.github/`, `.gitignore`, `.DS_Store`, `examples/`, `tests/`, `raycast/`

These are repo metadata, install scripts, holding-pen files for things we removed, or AI-agent instructions that must stay repo-local. `CLAUDE.md` is explicitly ignored because if it rendered into `$HOME` it would shadow the user-level `~/.config/claude/CLAUDE.md`; the repo-local copy is a one-line `@AGENTS.md` bridge that Claude Code picks up when started inside this repo. See [AI tools](ai-tools.md).

The Claude Code profile split is now handled inside `dot_config/claude/CLAUDE.md.tmpl`,
which uses `includeTemplate (printf "claude/%s.md" .profile)` to pull the active
profile body from `.chezmoitemplates/claude/`. Only one `CLAUDE.md` lands in
`$HOME` regardless of profile; no `.chezmoiignore` gating needed.

## Utility scripts (run by hand or via aliases)

Not synced to `$HOME` — these are tools you run from the repo itself.

| Script | What it does | When to run |
|---|---|---|
| `install.sh` | Guided bootstrap for a fresh Mac. Idempotent. | Once on a new machine; safe to re-run anytime. |
| `scripts/bootstrap-auth.sh` | Walks through 1Password, gh, optional az/gcloud auth, AKS/GKE plugin checks, and git-signing smoke test. | Once after `install.sh`. Safe to re-run — skips already-signed-in accounts and missing CLIs. |
| `scripts/doctor.sh` | Reads-only health check. Verifies XDG layout, Claude personal config, op signing, brew bundle drift, auth state, etc. Pass/warn/fail per check. | Anytime something feels off. Aliased as `chezdoctor`. |
| `scripts/macos-defaults.sh` | Idempotent system defaults. | On first apply and again whenever this script changes (chezmoi `run_onchange_after_*` keyed on its sha256); re-run by hand via the `macos-defaults` alias after macOS updates reset things. |
| `scripts/lib/semver.sh` | Sourced helper: `semver_extract` / `semver_lt`. Used by `doctor.sh` for the chezmoi version-minimum check. Unit-tested by `tests/semver.bats`. | Never run directly. |
| `tests/*.bats` | bats-core unit tests for shared shell helpers and zsh functions. Run in CI; run locally with `bats tests/`. | When changing shell helpers. |
| `tests/drive-wizard.py` | pty smoke test that drives `install.sh` end-to-end under `DRY_RUN` (always answers "No", so nothing is applied), guarding the wizard's TTY handling against hangs and regressions. See [wizard](wizard.md). | When changing `install.sh` or the `prompt_*` / TTY code. |

## chezmoi infrastructure (not files in `$HOME`, but used by chezmoi itself)

| File | Role |
|---|---|
| `.chezmoi.toml.tmpl` | Init prompts (name, email, signingKey, profile, workstation extras). Renders to `~/.config/chezmoi/chezmoi.toml` on `chezmoi init`. The `profile` value is available in every chezmoi script and template as `{{ .profile }}`. |
| `Brewfile`, `brewfiles/Brewfile.mac-apps`, `brewfiles/Brewfile.personal`, `brewfiles/Brewfile.work` | Workstation brew package list. `Brewfile` is always installed; the brew-bundle chezmoi script layers the mac apps module (GUI apps + AI tooling) and profile extras based on chezmoi data. |
| `vscode/extensions.txt` | VS Code marketplace extension manifest. The VS Code chezmoi script reads it directly from the source repo; it is not copied into `$HOME`. |
| `dot_config/zsh/dot_zshrc.tmpl` | Templated zshrc — includes profile-conditional blocks rendered only when `{{ .profile }}` matches. |
| `.chezmoiignore` | List of patterns to skip. |
| `.chezmoiscripts/run_once_before_01-install-homebrew.sh.tmpl` | Runs once before any apply. macOS-only via template guard. |
| `.chezmoiscripts/run_onchange_after_02-brew-bundle.sh.tmpl` | Runs after apply when Brewfile content hash changes. macOS-only. Installs `mise` (among the core formulae). |
| `.chezmoiscripts/run_onchange_after_02b-mise-install.sh.tmpl` | Runs after apply when the global mise config (`dot_config/mise/config.toml`) changes. Runs `mise install` to eagerly download the global runtimes (java, node) so the first interactive shell has them ready — the mise equivalent of an eager bootstrap. macOS-only, idempotent, doesn't fail the apply on a transient install error. |
| `.chezmoiscripts/run_onchange_after_02c-cleanup-deprecated.sh.tmpl` | Removes tooling the repo no longer manages, from an explicit in-script manifest: deprecated Homebrew formulae (`direnv`, `node`) + casks (`temurin@21`, `temurin@25`), the old out-of-band `devbox` binary, and leftover `~/.config/direnv` / devbox data dirs. Only touches named items (never a blanket sweep) and is guarded so it's a no-op on machines that never had them. The irreversible `/nix` store is removed only after an interactive y/N (skipped if there's no TTY). macOS-only. Re-fires only when the manifest changes — add future deprecations to the arrays at the top of the script. |
| `.chezmoiscripts/run_onchange_after_03-vscode.sh.tmpl` | Installs VS Code marketplace extensions from `vscode/extensions.txt`, uninstalls deprecated extensions such as Continue (plus the old `jetpack-io.devbox` and `mkhl.direnv`), and installs/updates the JetBrains Kotlin VSIX from the latest `Kotlin/kotlin-lsp` GitHub release. macOS-only. Runs when the script or extension manifest changes. |
| `.chezmoiscripts/run_onchange_after_04-macos-defaults.sh.tmpl` | Runs `scripts/macos-defaults.sh` on first apply and again **whenever that script changes** (`run_onchange_*`, keyed on a sha256 `include` of the defaults script). A routine apply that doesn't touch the script is a no-op, so you don't get a sudo prompt every time — but editing the defaults script now re-applies automatically, instead of silently doing nothing as the old `run_once_*` did. To re-apply without editing, run the `macos-defaults` zsh alias. The wrapper reopens stdin from `/dev/tty` so sudo's password prompt works through chezmoi's non-interactive script context. |
| `.chezmoiscripts/run_onchange_after_99-completion.sh.tmpl` | Prints a clear "✓ chezmoi apply complete" banner at the end of every apply. Always re-fires because the embedded `{{ now.Unix }}` timestamp makes the content hash differ on every render. The "99-" prefix sorts it after all other after-scripts. Pure UX — gives an unambiguous signal that chezmoi has finished its work. |
| `scripts/macos-defaults.sh` | The actual defaults script. Invoked by chezmoi on first apply (via the wrapper above) and re-runnable on demand via the `macos-defaults` zsh alias. |
| `scripts/setup-ollama.sh` | Optional local AI bootstrap. Starts Ollama as a brew service (Ollama ships in the mac-apps module). Pulls no models — download them manually with `ollama pull <model>`. |
| `scripts/lib/ui.sh` | Sourced helpers: `ui_init_colors` / `ui_init_glyphs`. Shared terminal color + glyph setup used by `doctor.sh`, `bootstrap-auth.sh`, and `setup-ollama.sh`. Never run directly. |

---

## What's in `$HOME` AFTER everything applies

These are the dotfiles/dirs that will remain — and the reason each one can't go elsewhere:

| Path | Why it can't move |
|---|---|
| `~/.zshenv` | zsh reads this BEFORE any environment variables are set. Hardcoded. |
| `~/.config/`, `~/.local/`, `~/.cache/` | These ARE the XDG dirs. They're where everything moved TO. |
| `~/.ssh/` | OpenSSH hardcodes `~/.ssh/` for keys, known_hosts, agent socket. Cannot move. |
| `~/.docker/` | Docker Desktop GUI writes here regardless of `DOCKER_CONFIG`. Moving the CLI config would create drift. |
| `~/Library/Application Support/Code/` | VS Code hardcodes this macOS user-data path for settings, extension state, snippets, and workspace storage. |
| `~/.m2/` | Maven 3.x doesn't have a clean XDG override. Maven 4 does (`MAVEN_USER_CONFIG_HOME`) — revisit when you move to mvn 4. |
| `~/.claude.json` | Claude Code session state, hardcoded path inside the binary. |
| `~/.CFUserTextEncoding`, `~/.Trash/` | macOS system files. |
| `Applications/`, `Desktop/`, `Documents/`, `Downloads/`, `Library/`, `Movies/`, `Music/`, `Pictures/`, `Public/`, `Dev/` | User folders, not dotfiles. |

That's the floor: the remaining unmanaged entries are either local state/cache, macOS-managed files, or app-hardcoded directories with managed config inside them.
