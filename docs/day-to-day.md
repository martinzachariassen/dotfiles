# Day-to-day

### Mental model: source → `$HOME`

`chezmoi apply` is **one-way**: it writes the source repo's files into `$HOME`, never the other direction. If you edit `~/.zshrc` directly with a text editor, the next `chezmoi apply` will either silently overwrite it (if it matches the last-known state) or prompt you to choose (if it's diverged).

The mental model that prevents accidents:

```sh
chezmoi edit ~/.zshrc            # opens the SOURCE file in $EDITOR (the right way)
chezmoi diff                     # preview what would change in $HOME
chez                             # smart-apply (recommended — see below)
chezmoi update                   # git pull + chezmoi apply
```

**Use `chez` instead of `chezmoi apply -v` for daily applies.** It's a wrapper function in `.zshrc` that:

1. Runs `chezmoi status` to summarize pending changes.
2. If anything is pending, shows the list and asks once: *"Apply (overwriting any local edits)? [y/N]"*.
3. If you say yes, runs `chezmoi apply --force` — which skips chezmoi's per-file confirmation prompts without dumping every file diff.

Why this matters: plain `chezmoi apply` opens an interactive prompt every time a managed file in `$HOME` has been modified externally. Those prompts read *single keypresses* (`d`/`o`/`s`/`q`/`m`), which collide badly with the `macos-defaults` sudo password prompt later in the same apply — the first character of your password gets eaten as a menu choice and you land in a diff view instead of authenticating. `chez` consolidates all chezmoi prompts into one yes/no upfront, so the only prompt you see *during* the apply is the sudo password (when it fires), with nothing else competing for your keystrokes.

If you accidentally edited a `$HOME` file directly and want to keep those changes, go the other direction:

```sh
chezmoi re-add ~/.zshrc          # captures live $HOME version back into source
chezmoi cd                       # cd to source repo
git diff                         # review
git add . && git commit -m "..."
```

### Toggling a feature on or off later

Features are workstation-level booleans in `~/.config/chezmoi/chezmoi.toml`. Project tools are not toggled here; pin them in that project's `mise.toml` instead. Use the `dotfiles` command for day-to-day workstation changes:

```sh
dotfiles features list
dotfiles features disable macApps
dotfiles features enable macApps

# Profiles use the same control path.
dotfiles profile set work

# Git signing can be updated after 1Password is signed in.
dotfiles signing set
```

For a guided flow on an existing machine, run `bash ~/Developer/personal/dotfiles/install.sh --configure-only`. It reuses the normal wizard prompts but skips Xcode/Homebrew/repo bootstrap. The signing command is narrower: it reapplies only the managed Git config files.

Disabling a feature does **not** uninstall the packages it pulled in — that's intentional, so you don't lose tools you've come to rely on. To actually remove a feature's packages:

```sh
brew bundle cleanup --force --file=~/Developer/personal/dotfiles/brewfiles/Brewfile.mac-apps
```

The old profile's packages stay until you `cleanup` them.

### Adding a new tool

Two flavors, depending on whether you just want the binary or also a config file.

**Workstation binary or app** — add it to the right Brewfile tier, commit, push:

```sh
dotfiles                                                   # cd ~/Developer/personal/dotfiles
echo 'brew "httpx"' >> Brewfile                            # or brewfiles/Brewfile.personal / brewfiles/Brewfile.work
git add Brewfile && git commit -m "Add httpx" && git push
chezmoi apply -v                                            # triggers brew-bundle re-run via hash change
```

**Project language runtime** — pin it in that project's `mise.toml` instead:

```sh
cd /path/to/project
mise use java@temurin-21 gradle@latest node@lts
```

CLIs (kubectl, terraform) and database servers (Postgres, Redis) are not mise's
job — install those from the Brewfile, or run datastores via Docker /
Testcontainers. For a starting point, copy one of [`examples/mise/`](../examples/mise/)
into the project as `mise.toml`.

### Starting a project with mise

Use this for any project with a repo-local language runtime: Java, Kotlin, Node,
Python, or anything else where the version should travel with the repo instead
of your global machine. `mise.toml` pins the runtimes and carries project env
vars; `mise activate` (wired into `.zshrc`) switches to them automatically when
you enter the directory and restores the global set when you leave.

```sh
cd /path/to/project
mise use java@temurin-21 gradle@latest node@lts   # replace with what the project needs
```

`mise use` writes (or updates) `mise.toml` in the current directory. Commit it:

```sh
git add mise.toml
git commit -m "chore(mise): pin project toolchain"
```

Project environment variables go in the file's `[env]` section instead of a
separate dotfile:

```toml
[env]
SPRING_PROFILES_ACTIVE = "local"
DATABASE_URL = "postgres://localhost:5432/app"
```

mise installs each runtime to a stable, version-named path (e.g.
`~/.local/share/mise/installs/java/temurin-21/Contents/Home`), so onboarding is
`git clone && cd` — mise installs any missing pinned versions on first entry,
with nothing machine-local baked into the repo.

You do not need this for projects with no local runtime or environment
variables; the global defaults from `~/.config/mise/config.toml` apply
everywhere else.

**With a config file you want to manage** — install, configure, then adopt:

```sh
brew install httpx
# configure httpx to your liking, generating ~/.config/httpx/config.toml
chezmoi add ~/.config/httpx/config.toml                    # captures into source
chezmoi cd
git add . && git commit -m "Add httpx + config" && git push
```

### Previewing changes before applying

`chezmoi diff` only shows changes to *managed dotfiles* (things that get written to `$HOME`). It does **not** show changes to the Brewfile, scripts, or repo metadata. To see all source changes, use `git diff`. To preview what brew bundle would actually install, use `brew bundle check`.

```sh
chezmoi diff                                                # what would change in $HOME
git diff                                                    # all source-side changes (incl. Brewfile)
brew bundle check --verbose --file=Brewfile                 # what brew bundle would install
chezmoi apply --dry-run -v 2>&1 | grep run_                 # raw script re-runs, including every-apply hooks
```

### Shell aliases & shortcuts

All defined in `~/.config/zsh/.zshrc`. Quick reference so you don't have to dig.

```sh
# Git
g, gs, gd, gl                # git, status -sb, diff, log --graph

# Navigation
..,  ...                     # cd .. / cd ../..
dotfiles                     # cd ~/Developer/personal/dotfiles

# chezmoi — everyday
chezup                       # converge this Mac to the repo: `git pull --ff-only` then apply. Every apply now reconciles real installed state, so this also installs any missing brew/mise packages (no separate fix step). The most common command.
chezdoctor                   # full health check (XDG layout, Claude personal config, op signing, brew sync, auth state)

# chezmoi — advanced / occasional
chez                         # smart `chezmoi apply` without pulling — diff preview + auto-force, no mid-apply prompt collisions. The building block chezup calls
chezreinit                   # pull + `chezmoi init` (re-renders chezmoi.toml from the latest template, prompting only for new keys) + apply. Use after a data-model change upstream
chezbump                     # routine bump: brew update/upgrade + brew bundle cleanup --dry-run + mise upgrade
chezaudit                    # report brew packages installed locally but not tracked in any Brewfile

# Modern CLI replacements (only activate if the tool is installed)
ls, ll, tree                 # eza variants
cat                          # bat (use `command cat` or `\cat` to bypass)
find                         # fd

# Tool shortcuts
n                            # nvim
lg                           # lazygit (interactive git TUI)
d, dc                        # docker, docker compose
tf                           # terraform
mw, gw                       # ./mvnw, ./gradlew (project wrappers)
k, kgp, klf                  # kubectl, kubectl get pods, kubectl logs -f

# Functions
mkcd <dir>                   # mkdir -p <dir> && cd into it

# Terminal multiplexer
zj                           # zellij attach -c default — named session, detach/reattach friendly

# Maintenance ceremonies (run on demand, NOT on every chezmoi apply)
macos-defaults               # re-apply system settings (sudo prompt; idempotent)
```

### Pinning Neovim plugins

The Neovim setup is a LazyVim bootstrap (`dot_config/nvim/lua/config/lazy.lua`).
Although `defaults.version = false` lets plugins track their latest commit, the
resolved set is **pinned via lazy.nvim's lockfile, which IS tracked in chezmoi**
(`dot_config/nvim/lazy-lock.json`). A fresh machine therefore gets the exact same
commits, not whatever is current that day.

Reproduce on a new machine — after the first launch installs the plugins:

```vim
:Lazy restore                          " check out the commits recorded in lazy-lock.json
```

Bump versions deliberately:

```sh
# inside nvim:
:Lazy update                           # update + rewrite ~/.config/nvim/lazy-lock.json
# confirm everything still loads, then back in the shell:
chezmoi add ~/.config/nvim/lazy-lock.json
chezmoi cd && git commit -am "chore(nvim): bump plugin lockfile" && git push
```

Tradeoff: `:Lazy update`/`:Lazy sync` rewrite the live lockfile, so it shows as
chezmoi drift until you re-add it — which is the point: you bump on purpose.

### JetBrains IDE settings

IntelliJ IDEA ships in the `mac-apps` Brewfile tier, but its **settings are not
managed by this repo** — JetBrains config is large, version-specific, and noisy
to diff, so chezmoi-tracking it tends to create churn for little benefit. Use
JetBrains' own sync instead:

- **Settings Sync** (*Settings → Settings Sync → Enable*) — backs keymaps,
  editor settings, plugins, and themes to your JetBrains account and syncs them
  across machines. Easiest option; recommended for most setups.
- **Settings Repository** (*File → Manage IDE Settings → Settings Repository*) —
  points the IDE at a private git repo you control, if you prefer git over the
  JetBrains account. Keep that repo separate from this dotfiles repo.

Either way, the only thing this repo owns is *installing* the IDE; the IDE owns
its own configuration.

### Diagnosing problems: doctor.sh

`bash ~/Developer/personal/dotfiles/scripts/doctor.sh` (or `chezdoctor`) is the single command for "is this machine in the state it should be?". It's read-only and idempotent. It reports pass / warn / fail across:

- **Source repo** — exists, on the right branch, in sync with origin, working tree clean.
- **chezmoi** — installed, `chezmoi doctor` is clean, no source/$HOME drift.
- **XDG layout** — no legacy `~/.zshrc`, `~/.gitconfig`, `~/.zprofile`; `~/.config/zsh/.zshrc` and `~/.zshenv` present.
- **Claude config** — `CLAUDE_CONFIG_DIR` points at `~/.config/claude`, and both `CLAUDE.shared.md` and the profile-rendered `CLAUDE.md` are present.
- **Git signing** — `op-ssh-sign` exists, signing key configured, smoke test of `git -S commit` actually succeeds.
- **Brew packages** — every workstation/profile Brewfile satisfied; reports brew packages installed locally but not tracked in any Brewfile.
- **mise** — `mise` installed via Homebrew, activation wired into the shell, global `~/.config/mise/config.toml` present, and the global runtimes (Temurin JDK 21 + 25, Node LTS) installed to their stable paths.
- **Cloud auth** — informational status of `gh`, `az`, `gcloud`, `op` when present.
- **Fonts** — JetBrainsMono Nerd Font installed.
- **Privacy permissions** — printed checklist (these can't be checked programmatically).

Exit code is 0 unless something fails (warnings don't fail the run). Wire it into a launchd plist if you want a weekly drift report.
