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

Features are workstation-level booleans in `~/.config/chezmoi/chezmoi.toml`. Project tools are not toggled here; add them to that project's `devbox.json` instead. Use the `dotfiles` command for day-to-day workstation changes:

```sh
dotfiles features list
dotfiles features enable ai
dotfiles features disable macApps
dotfiles features enable macApps

# Profiles use the same control path.
dotfiles profile set work
dotfiles profile set both

# Git signing can be updated after 1Password is signed in.
dotfiles signing set
```

For a guided flow on an existing machine, run `bash ~/Developer/personal/dotfiles/install.sh --configure-only`. It reuses the normal wizard prompts but skips Xcode/Homebrew/repo bootstrap. The signing command is narrower: it reapplies only the managed Git config files.

Disabling a feature does **not** uninstall the packages it pulled in — that's intentional, so you don't lose tools you've come to rely on. To actually remove a feature's packages:

```sh
brew bundle cleanup --force --file=~/Developer/personal/dotfiles/brewfiles/Brewfile.ai
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

**Project toolchain** — add it to that project's Devbox config instead:

```sh
cd /path/to/project
devbox add terraform tflint terraform-docs
devbox add kubectl kubectx k9s stern kubernetes-helm
devbox add postgresql_16 redis pgcli
```

For a starting point, copy one of [`examples/devbox/`](../examples/devbox/) into the project as `devbox.json`.

### Starting a project with Devbox + direnv

Use this for any project with repo-local tooling: Java, Kotlin, Node, Terraform,
Kubernetes, database clients, or anything else where the version should travel
with the repo instead of your global machine. Devbox defines the toolchain;
direnv activates it automatically when you enter the directory and unloads it
when you leave.

```sh
cd /path/to/project
devbox init
devbox add jdk21 maven              # replace with the tools this project needs
devbox generate direnv
```

Commit the generated files:

```sh
git add devbox.json devbox.lock .envrc
git commit -m "chore(devbox): add project toolchain"
```

`devbox generate direnv` writes an `.envrc` equivalent to:

```sh
eval "$(devbox generate direnv --print-envrc)"
```

That line asks devbox to emit the current environment for this project. Keeping
it generated instead of hand-writing `PATH`/`JAVA_HOME` avoids baking Nix store
paths or machine-local details into the repo.

For projects under `~/Developer`, this dotfiles setup auto-trusts `.envrc`
files. Elsewhere, run `direnv allow` once after reviewing the file.

You do not need this for projects that have no local toolchain or environment
variables. When a repo does use devbox, pair it with direnv by default; otherwise
every terminal and editor session needs a manual `devbox shell`.

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
chezmoi apply --dry-run -v 2>&1 | grep run_                 # which chezmoi scripts would re-fire
```

### Shell aliases & shortcuts

All defined in `~/.config/zsh/.zshrc`. Quick reference so you don't have to dig.

```sh
# Git
g, gs, gd, gl                # git, status -sb, diff, log --graph

# Navigation
..,  ...                     # cd .. / cd ../..
dotfiles                     # cd ~/Developer/personal/dotfiles

# chezmoi
chez                         # smart `chezmoi apply` — diff preview + auto-force, no mid-apply prompt collisions
chezup                       # `git pull --ff-only` in the source repo, then chez — most common upgrade workflow
chezreinit                   # pull + `chezmoi init` (re-renders chezmoi.toml from the latest template, prompting only for new keys) + chez. Use after a data-model change upstream
chezdiff                     # chezmoi diff + brew bundle drift across every Brewfile module + which scripts would re-fire
chezbump                     # routine bump: brew update/upgrade + brew bundle cleanup --dry-run + devbox global update
chezaudit                    # report brew packages installed locally but not tracked in any Brewfile
chezdoctor                   # full health check (XDG layout, Claude personal config, op signing, brew sync, auth state)

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

### Diagnosing problems: doctor.sh

`bash ~/Developer/personal/dotfiles/scripts/doctor.sh` (or `chezdoctor`) is the single command for "is this machine in the state it should be?". It's read-only and idempotent. It reports pass / warn / fail across:

- **Source repo** — exists, on the right branch, in sync with origin, working tree clean.
- **chezmoi** — installed, `chezmoi doctor` is clean, no source/$HOME drift.
- **XDG layout** — no legacy `~/.zshrc`, `~/.gitconfig`, `~/.zprofile`; `~/.config/zsh/.zshrc` and `~/.zshenv` present.
- **Claude personal config** — wrapper loads and `~/.config/claude/personal` is present.
- **Git signing** — `op-ssh-sign` exists, signing key configured, smoke test of `git -S commit` actually succeeds.
- **Brew packages** — every workstation/profile Brewfile satisfied; reports brew packages installed locally but not tracked in any Brewfile.
- **devbox + direnv + Nix** — devbox CLI installed, `/nix` store mounted, `nix-daemon` running, direnv hook wired into the shell, global direnv config present, no leftover `mise` on PATH.
- **Cloud auth** — informational status of `gh`, `az`, `gcloud`, `op` when present.
- **Fonts** — JetBrainsMono Nerd Font installed.
- **Privacy permissions** — printed checklist (these can't be checked programmatically).

Exit code is 0 unless something fails (warnings don't fail the run). Wire it into a launchd plist if you want a weekly drift report.
