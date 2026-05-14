# dotfiles

[![CI](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Managed by chezmoi](https://img.shields.io/badge/managed%20by-chezmoi-66ccff)](https://chezmoi.io)
[![Catppuccin Frappé](https://img.shields.io/badge/Catppuccin-Frapp%C3%A9-f2d5cf?labelColor=303446)](https://github.com/catppuccin/catppuccin)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> Personal macOS setup, managed by [chezmoi](https://chezmoi.io). One command bootstraps a fresh Mac into a clean backend workstation — terminal, multiplexer, prompt, editors, Devbox-powered project environments, GUI apps, and macOS system defaults all in their final state.

## Table of Contents

- [Bootstrap](#bootstrap)
  - [The six phases](#the-six-phases)
  - [Profiles & features](#profiles--features)
  - [Day-one secrets and signing](#day-one-secrets-and-signing)
  - [Privacy permissions checklist](#privacy-permissions-checklist)
- [What you get](#what-you-get)
  - [What the prompt looks like](#what-the-prompt-looks-like)
- [Day-to-day](#day-to-day)
  - [Mental model: source → `$HOME`](#mental-model-source--home)
  - [Toggling a feature on or off later](#toggling-a-feature-on-or-off-later)
  - [Adding a new tool](#adding-a-new-tool)
  - [Previewing changes before applying](#previewing-changes-before-applying)
  - [Shell aliases & shortcuts](#shell-aliases--shortcuts)
  - [Diagnosing problems: doctor.sh](#diagnosing-problems-doctorsh)
- [Upgrading when upstream changes](#upgrading-when-upstream-changes)
- [Claude Code: work vs personal](#claude-code-work-vs-personal)
- [Codex global instructions](#codex-global-instructions)
- [Forking this repo](#forking-this-repo)
- [Architecture](#architecture)
- [Troubleshooting](#troubleshooting)
- [Uninstall / reset](#uninstall--reset)
- [Reference](#reference)
- [License](#license)

---

## Bootstrap

On a fresh Mac (or an existing one), open Terminal and run:

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

You'll meet a guided terminal wizard with numbered menus and normal text fields. It deliberately avoids raw-mode arrow-key prompts so it works in plain Terminal, Ghostty, remote shells, and pasted `curl | bash` sessions. Every prompt is batched in Phase B; once you confirm in Phase C the install runs unattended except for system prompts such as Xcode CLT or sudo. Total time is usually ~15 min, almost all of it Homebrew downloading.

```text
+  Dotfiles setup
|  Reliable numbered wizard for a fresh or existing Mac.
|
>  Phase B - Choices
|
|  How to use this screen: enter numbers for menus, type text into fields,
|  or press Enter to keep the shown default.
|
>  Profile
|    1. personal - personal extras only
|    2. work - work extras only
|    3. both - personal and work extras (current)
|  Choose 1-3, or leave blank for both:
```

The wizard is idempotent. Re-run it any time — it detects existing state, shows current values as defaults, lets you change profile/identity/features, and skips steps that are already done.

Useful environment variables:

```sh
DRY_RUN=1         bash install.sh   # print state-changing commands without running them
YES=1             bash install.sh   # accept recommended defaults at every prompt (good for CI / reinstalls)
SKIP_BACKUP=1     bash install.sh   # don't snapshot pre-existing legacy dotfiles
DOTFILES_REPO=…   bash install.sh   # point at a fork
DOTFILES_DIR=…    bash install.sh   # clone somewhere other than ~/Dev/Personal/dotfiles
```

For a Homebrew cleanup, there are two guarded modes:

```sh
bash install.sh --mirror-brew  # remove packages not in the active Brewfiles
bash install.sh --reset-brew   # uninstall everything first, then reinstall
```

Mirror mode keeps packages from the active set: `Brewfile`, enabled feature Brewfiles such as `Brewfile.mac-apps`, and the selected profile Brewfile(s). It removes local Homebrew packages outside that set. Reset mode uninstalls every current Homebrew formula and cask, then lets `chezmoi apply` reinstall the repo-managed set. In interactive runs you must type `MIRROR BREW` or `RESET BREW` before the cleanup proceeds.

On an already-bootstrapped machine, use the short configuration path when you
only want to change profile, identity, or feature toggles:

```sh
bash install.sh --configure-only
```

### The six phases

| Phase | Name | What it does |
|---|---|---|
| **A** | Discovery | Read-only probe of macOS version + arch, Xcode CLT, Homebrew, chezmoi, existing repo clone, prior chezmoi config, 1Password.app, and legacy files (`~/.zshrc`, `~/.gitconfig`, oh-my-zsh, …). Nothing changes here. |
| **B** | Choices | Numbered profile picker. Identity text fields with existing values as defaults. 1Password yes/no; if yes, paste the public signing key. Workstation extras — currently macOS quality-of-life apps. Existing-system handling (Homebrew mirror/reset? back up + remove legacy files? uninstall oh-my-zsh?). |
| **C** | Confirm | One-screen summary of every choice. Last chance to abort. |
| **D** | Execute | Backs up legacy files (to `~/.dotfiles-backup-<timestamp>/`), optionally resets Homebrew, installs Xcode CLT (polls the GUI dialog up to 20 min), Homebrew, chezmoi, clones the repo, runs `chezmoi init` with all answers pre-supplied (zero prompts), then `chezmoi apply` — which fans out to `brew bundle` against core + workstation/profile extras, plus macOS defaults (sudo once). |
| **E** | Self-test | Functional checks for the workstation baseline. Reports auth state for `gh`/`az`/`gcloud` as FYI when those tools are present. |
| **F** | Next steps | Prints the exact follow-ups: sign in to 1Password, run `bootstrap-auth.sh`, `exec zsh`, restart. |

After the wizard finishes:

```sh
# 1. Sign in to 1Password (so SSH agent + git signing work) — skip if you said no in Phase B
open -a 1Password

# 2. Walk through CLI auth (gh, az, gcloud, AKS/GKE plugins, signing test). Idempotent.
bash ~/Dev/Personal/dotfiles/bootstrap-auth.sh

# 3. Reload shell with the new config
exec zsh

# 4. Restart the Mac so all macOS defaults take full effect
sudo shutdown -r now
```

### Profiles & features

Phase B asks two orthogonal questions: which **profile** you're on (which casks/aliases get layered in) and which workstation **extras** you want globally.

**Profile** controls personal-vs-work cask + shell-config layering:

| Profile | Brewfiles applied (on top of core) | Notes |
|---|---|---|
| `personal` | `Brewfile.personal` | Personal-only apps you add. Personal-only `.zshrc` block renders. |
| `work` | `Brewfile.work` | Work-only apps you add (Claude Code, Slack, Teams, Postman, etc.). Work-only `.zshrc` block renders, including `~/.storecode/bin` on PATH if installed. |
| `both` | both | Single-machine-many-jobs. |

**Features** are intentionally narrow. Project toolchains are Devbox-owned; Homebrew features are only for workstation-level preferences:

| Feature | Brewfile | What's in it |
|---|---|---|
| `macApps` | `Brewfile.mac-apps` | Rectangle, Raycast, Stats, Chrome, dive. Pure QoL — skip on a server-y machine. |

The core `Brewfile` always installs the workstation baseline: git, modern CLI, prompt, zsh tooling, Ghostty, VS Code, 1Password GUI + CLI, Docker Desktop, Nerd Fonts, Neovim, `direnv`, `az`, `gcloud`, and other shell primitives. Project-pinned Kubernetes tools, Terraform/OpenTofu, database clients/servers, and language runtimes belong in each project's `devbox.json`. Starter templates live under [`examples/devbox/`](examples/devbox/).

To flip a profile or feature later:

```sh
dotfiles profile set work
dotfiles profile set personal
dotfiles features list
dotfiles features disable macApps
```

`dotfiles` with no arguments still jumps to the source repo. With arguments it
updates `~/.config/chezmoi/chezmoi.toml` and runs `chezmoi apply --force`.

### Day-one secrets and signing

The bootstrap pulls config and tools, but **secrets aren't in this repo on purpose**. Here's where they actually come from on a fresh Mac.

**SSH keys** — both authentication and git signing use the **1Password SSH agent**, not files on disk. Once you sign in to 1Password and enable *Settings → Developer → SSH agent*, every SSH key in your vault becomes available to `ssh`, `git`, and anything else that talks to `$SSH_AUTH_SOCK`. There are no `~/.ssh/id_*` private keys to copy across machines — that's the whole point. Public keys for known_hosts you'll have to accept once per host.

**Git commit signing** — chezmoi's init prompt asks for `signingKey`, which is your **public key** copied from the 1Password item. The corresponding private key never leaves 1Password; `op-ssh-sign` (bundled with the 1Password macOS app) signs commits via the agent. The git config template at `dot_config/git/config.tmpl` wires `[gpg "ssh"] program = /Applications/1Password.app/Contents/MacOS/op-ssh-sign` for you. `bootstrap-auth.sh` runs a `git -S` smoke test against an empty repo to prove the whole chain (1Password unlocked → agent reachable → signing key found → signed commit succeeds) actually works.

**Cloud auth tokens** — `gh`, `az`, and `gcloud` each store their own credentials under `~/.config/gh/`, `~/.azure/`, `~/.config/gcloud/`. These account CLIs are global because auth, subscriptions/projects, and bootstrap checks are workstation concerns. Project-specific CLIs still stay in Devbox. `bootstrap-auth.sh` walks through whichever CLIs are installed and skips the rest. None of these directories are tracked in this repo.

**1Password CLI** (`op`) — separate from the GUI sign-in. First run on a machine: `op account add` (paste account URL + secret key), then `eval $(op signin)`. Subsequent shell sessions: `eval $(op signin)`.

### Privacy permissions checklist

macOS won't let any script grant Privacy permissions; you have to click them in *System Settings → Privacy & Security*. None of these break on day one but several of your tools silently won't work right until granted. The checklist:

- **Full Disk Access** → your terminal (Ghostty). Required for the Safari `defaults write` calls in `macos-defaults.sh` to actually apply, and for some `find` operations against protected dirs.
- **Accessibility** → Rectangle, Raycast, and Karabiner-Elements (if you use it). Without this, Rectangle can't move windows and Raycast can't simulate keystrokes.
- **Screen Recording** → Raycast (for screenshot features), and any screenshot/screen-share tools.
- **Input Monitoring** → Karabiner-Elements (if used). Without it, Karabiner can't see your keystrokes.
- **Developer Tools** → your terminal. Reduces Gatekeeper friction when running locally-built binaries.
- **Automation** → grant your terminal the right to control whichever apps you script via `osascript`.

Run `chezdoctor` for a reminder. The script can't verify these for you, but it prints the list at the end.

---

## What you get

| Area | What's in the box |
|---|---|
| **Terminal** | [Ghostty](https://ghostty.org) with Catppuccin Frappé, JetBrainsMono Nerd Font, transparent titlebar, blurred background. Theme YAML at `~/.config/ghostty/themes/catppuccin-frappe` (chezmoi-managed, so it's deterministic across Ghostty versions). |
| **Multiplexer** | [Zellij](https://zellij.dev) with the Catppuccin Frappé theme, compact layout, mouse + clipboard integration, session persistence. Launch with the `zj` alias. Auto-attach on shell startup is opt-in (commented snippet in `.zshrc`). |
| **Prompt** | [Starship](https://starship.rs) with Catppuccin Frappé palette. Two-line prompt that surfaces git branch/status, language versions (Java/Node/Python/Go), Kubernetes context, and AWS profile only when contextually relevant — keeps it clean otherwise. See [the prompt examples](#what-the-prompt-looks-like) below. |
| **Shell** | zsh with full XDG layout, direnv hook (auto-activates each project's devbox env on `cd`), fzf integration (`Ctrl-R` history search, `**<Tab>` completion), `zsh-completions` + `zsh-syntax-highlighting`, claude work/personal wrapper, modern CLI aliases (`ls→eza`, `cat→bat`, `find→fd`). |
| **Git** | Identity + 1Password commit signing via `op-ssh-sign`, delta diffs, useful aliases (`s`, `lg`, `wip`, `undo`, `amend`, `fixup`), pull rebase, rerere. |
| **Runtimes and project CLIs** | **Per-project** via [Devbox](https://www.jetify.com/devbox) (Nix-backed). Each project's repo carries its own `devbox.json` + `.envrc`; on `cd` direnv activates the project's pinned JDK/Kotlin/Postgres/Node/Terraform/kubectl/etc. without polluting the global PATH. Devbox itself isn't in homebrew — `.chezmoiscripts/run_onchange_before_01b-install-devbox.sh.tmpl` handles both the Jetify curl-installer for the CLI and the Determinate Nix bootstrap for the `/nix` store. Starter templates for backend, Kubernetes, Terraform, and OpenTofu projects live in [`examples/devbox/`](examples/devbox/). Azure/GCP account CLIs stay global; the project-specific Kubernetes/IaC tools stay pinned here. |
| **Brew** | Workstation baseline + per-profile extras. Full list with one-line rationale per package in [`Brewfile`](Brewfile). Categories: modern CLI, git productivity (`lazygit`, `pre-commit`, `direnv`), shell/editor tools, global account CLIs (`gh`, `az`, `gcloud`), Docker Desktop, Ghostty, VS Code, 1Password, fonts, and optional GUI apps. Project-specific tools such as Kubernetes CLIs, Terraform/OpenTofu, DB clients/servers, and language runtimes are intentionally Devbox-owned. |
| **Editor (GUI)** | VS Code is installed by Homebrew. User settings, keybindings, snippets, and extensions are left to VS Code Settings Sync. |
| **Editor (terminal)** | [Neovim](https://neovim.io) with [LazyVim](https://www.lazyvim.org) and the Catppuccin Frappé flavor. First launch auto-installs `lazy.nvim`, then LazyVim pulls in LSP (via mason), treesitter, telescope, nvim-tree, which-key, gitsigns, and the standard distribution. Backend-dev language extras (Java/Python/TypeScript/JSON/YAML/Docker/Terraform/Markdown) ship commented-out in `lua/config/lazy.lua` — uncomment whichever you want. |
| **macOS** | Fast key repeat, no autocorrect, full keyboard nav, Finder shows everything, Dock auto-hide, screenshots → `~/Pictures/Screenshots`, Safari dev menu, screensaver password immediately. Idempotent — `def_write` helper only writes when the value differs from current. |

Full source-to-destination mapping in [`MAPPING.md`](MAPPING.md).

### What the prompt looks like

Starship modules show up only when contextually relevant, so the prompt grows with the situation. A few examples (rendered plain here; in Ghostty they're Catppuccin-tinted):

```text
# Plain directory, no git, no project — minimal noise
~/Dev ❯

# Inside a git repo on a clean branch
~/Dev/Personal/dotfiles on  main ❯

# Java project on a feature branch with 2 modified + 1 untracked file
~/Dev/Work/api on  feat/auth  2 ?1  via  21.0.5 ❯

# Same project, now with a Kubernetes context active because k8s/ exists
~/Dev/Work/api on  feat/auth via  21.0.5 ⎈ prod (default) ❯

# After a slow command (>2s), the right-side block shows the duration
~/Dev/Work/api on  main ❯ mvn test                              took 47s
```

The `❯` prompt char turns red on a non-zero exit status. Language icons require a Nerd Font (JetBrainsMono Nerd Font, installed by the Brewfile and set in Ghostty).

---

## Day-to-day

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
3. If you say yes, runs `chezmoi apply -v --force` — which skips chezmoi's per-file confirmation prompts.

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
dotfiles features disable macApps
dotfiles features enable macApps

# Profiles use the same control path.
dotfiles profile set work
dotfiles profile set both
```

For a guided flow on an existing machine, run `bash ~/Dev/Personal/dotfiles/install.sh --configure-only`. It reuses the normal wizard prompts but skips Xcode/Homebrew/repo bootstrap.

Disabling a feature does **not** uninstall the packages it pulled in — that's intentional, so you don't lose tools you've come to rely on. To actually remove the mac app extras:

```sh
brew bundle cleanup --force --file=~/Dev/Personal/dotfiles/Brewfile.mac-apps
```

The old profile's packages stay until you `cleanup` them.

### Adding a new tool

Two flavors, depending on whether you just want the binary or also a config file.

**Workstation binary or app** — add it to the right Brewfile tier, commit, push:

```sh
dotfiles                                                   # cd ~/Dev/Personal/dotfiles
echo 'brew "httpx"' >> Brewfile                            # or Brewfile.personal / Brewfile.work
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

For a starting point, copy one of [`examples/devbox/`](examples/devbox/) into the project as `devbox.json`.

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
dotfiles                     # cd ~/Dev/Personal/dotfiles

# chezmoi
chez                         # smart `chezmoi apply` — diff preview + auto-force, no mid-apply prompt collisions
chezup                       # `git pull --ff-only` in the source repo, then chez — most common upgrade workflow
chezreinit                   # pull + `chezmoi init` (re-renders chezmoi.toml from the latest template, prompting only for new keys) + chez. Use after a data-model change upstream
chezdiff                     # chezmoi diff + brew bundle drift across every Brewfile module + which scripts would re-fire
chezbump                     # routine bump: brew update/upgrade + brew bundle cleanup --dry-run + devbox global update
chezaudit                    # report brew packages installed locally but not tracked in any Brewfile
chezdoctor                   # full health check (XDG layout, claude routing, op signing, brew sync, auth state)

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

# Claude Code profile (also auto-routes by PWD)
cw                           # work profile      (CLAUDE_CONFIG_DIR=~/.claude)
cme                          # personal profile  (CLAUDE_CONFIG_DIR=~/.config/claude/personal)

# Maintenance ceremonies (run on demand, NOT on every chezmoi apply)
macos-defaults               # re-apply system settings (sudo prompt; idempotent)
```

### Diagnosing problems: doctor.sh

`bash ~/Dev/Personal/dotfiles/doctor.sh` (or `chezdoctor`) is the single command for "is this machine in the state it should be?". It's read-only and idempotent. It reports pass / warn / fail across:

- **Source repo** — exists, on the right branch, in sync with origin, working tree clean.
- **chezmoi** — installed, `chezmoi doctor` is clean, no source/$HOME drift.
- **XDG layout** — no legacy `~/.zshrc`, `~/.gitconfig`, `~/.zprofile`; `~/.config/zsh/.zshrc` and `~/.zshenv` present.
- **Claude routing** — wrapper loads, routes correctly from `/tmp` (personal) and `~/Dev/Work/` (work), `~/.claude` present if work profile.
- **Git signing** — `op-ssh-sign` exists, signing key configured, smoke test of `git -S commit` actually succeeds.
- **Brew packages** — every workstation/profile Brewfile satisfied; reports brew packages installed locally but not tracked in any Brewfile.
- **devbox + direnv + Nix** — devbox CLI installed, `/nix` store mounted, `nix-daemon` running, direnv hook wired into the shell, global direnv config present, no leftover `mise` on PATH.
- **Cloud auth** — informational status of `gh`, `az`, `gcloud`, `op` when present.
- **Fonts** — JetBrainsMono Nerd Font installed.
- **Privacy permissions** — printed checklist (these can't be checked programmatically).

Exit code is 0 unless something fails (warnings don't fail the run). Wire it into a launchd plist if you want a weekly drift report.

---

## Upgrading when upstream changes

Once your machine is on this setup, keeping it in sync with what's pushed upstream is one command in the common case and one slightly bigger command for the rare "the wizard changed" case.

### The 95% case: just pull and apply

```sh
chezup
```

Defined in your `.zshrc`. It does:

1. `git pull --ff-only` in `~/Dev/Personal/dotfiles`
2. `chez` — chezmoi status + a single-keypress confirm + `chezmoi apply -v --force`

That handles everything chezmoi knows how to handle: new dotfiles, edited templates, added/removed workstation packages in any Brewfile, and modified scripts. Project-level Devbox changes are applied when you enter that project or run `devbox install` there. VS Code settings and extensions are handled by VS Code Settings Sync, not this repo.

`chezup` is also a no-op when nothing changed — safe to run as often as you like (e.g., wire it into a launchd timer for a daily auto-sync if you want).

### The 5% case: the wizard's data model or chezmoi config changed

Sometimes a push will add a new prompt to the wizard (a new workstation feature toggle, a new boolean for "do you use X?"), or change a chezmoi-level setting like `[apply] force = true` or `[diff] pager`. When that happens, your existing `~/.config/chezmoi/chezmoi.toml` is stale — `chezmoi apply` reads the on-disk config and won't see the new sections. Templates use defensive defaults for feature toggles, but `[apply]`/`[diff]` settings only take effect after a re-init.

To pull the new sections into your on-disk config:

```sh
chezreinit
```

That's `git pull` + `chezmoi init` + `chez`. `chezmoi init` re-renders `chezmoi.toml` from the latest template; `promptOnce` keeps every answer you've already given and only prompts for fields that don't have a value yet. Idempotent — running it on a fully-up-to-date config is a no-op.

**Telltale sign you need `chezreinit` rather than `chezup`:** you're seeing prompts or behaviour from `chezmoi apply` that the docs say should be silent (e.g. per-file `diff/overwrite/skip` prompts after `[apply] force = true` was added, or unpaged diffs after `[diff] pager` was changed).

If you'd rather walk through the full wizard again (e.g., to flip a workstation feature toggle visually rather than by editing TOML), just rerun:

```sh
bash ~/Dev/Personal/dotfiles/install.sh
```

It'll detect your existing config in Phase A and ask whether to re-use prior answers; say no to get the full multi-select again.

### How the invalidation rules work

Knowing what triggers what makes the upgrade story less mysterious:

| You edit / pull… | Triggers on next `chezmoi apply` |
|---|---|
| Any file under `dot_*` or `private_dot_*` | chezmoi writes it to `$HOME` |
| A `.tmpl` template | chezmoi re-renders it against your current `[data]` block |
| Any tracked `Brewfile*` | `run_onchange_after_02-brew-bundle.sh` re-fires (hash comment caught it) |
| `.chezmoi.toml.tmpl` itself | **nothing automatic** — you must run `chezmoi init` (or `chezreinit`) to re-render `~/.config/chezmoi/chezmoi.toml`. This is the only common case where `chezup` alone is insufficient |
| `macos-defaults.sh` | nothing — it's `run_once_after`. Manually run `macos-defaults` (the alias) to re-apply |

If you forget which path you're on, `chezdiff` shows you everything pending at once: chezmoi's dotfile diff, brew-bundle drift across every tracked Brewfile, and which `run_*` scripts would re-fire. It's the "what would chezup actually do" preview.

### Cleaning up packages from features you've turned off

Disabling a feature toggle stops that Brewfile from being re-applied, but does **not** uninstall the packages it pulled in — intentional, so you don't lose tools you might still use. To actually remove the current mac-apps feature packages:

```sh
brew bundle cleanup --force --file=~/Dev/Personal/dotfiles/Brewfile.mac-apps
```

`chezaudit` (alias) shows you packages currently installed that aren't tracked in any Brewfile, which is useful when you've manually `brew install`ed something and want to decide whether to promote it into a workstation Brewfile, move it into a project Devbox, or remove it.

### What to do after a long absence (machine sitting idle for weeks)

```sh
chezreinit         # pull + init + apply — handles data-model drift in one shot
chezbump           # brew update/upgrade + devbox global update
chezdoctor         # full health check — surfaces anything that broke while you were away
```

---

## Claude Code: work vs personal

A wrapper function in `.zshrc` routes `claude` based on PWD:

- Anywhere under `~/Dev/Work/` → uses `~/.claude` (work profile, managed by employer's tooling — see [`WORK-SETUP.md`](WORK-SETUP.md))
- Everywhere else → uses `~/.config/claude/personal`

Override with `cw` (work) or `cme` (personal) aliases, or `CLAUDE_PROFILE=work claude …` for one-off.

The CLI binary comes from the `cask "claude-code"` line in `Brewfile.work`; it is intentionally installed only for the work profile.

### Global CLAUDE.md

[`dot_config/claude/personal/CLAUDE.md`](dot_config/claude/personal/CLAUDE.md) is auto-loaded into every personal Claude Code session — covers communication style, the tool environment Claude can assume is available, language-specific code-style preferences, and explicit anti-patterns ("don't suggest tmux, I use Zellij"). Edit via `chezmoi edit ~/.config/claude/personal/CLAUDE.md` to keep it in sync with your source. Project-specific instructions go in `<project>/CLAUDE.md` and merge on top of this global one.

---

## Codex global instructions

[`dot_codex/AGENTS.md`](dot_codex/AGENTS.md) maps to `~/.codex/AGENTS.md` and is loaded into every personal Codex session before project-level instructions. It mirrors the same personal defaults as `CLAUDE.md`: communication style, local tooling, backend stack preferences, code-style choices, and commit conventions. Project-specific Codex instructions go in `<project>/AGENTS.md` and layer on top.

---

## Forking this repo

The wizard is designed to be fork-friendly. If you cloned this and want to base your own setup on it, here's the minimum surface area you'll want to touch:

1. **Point `install.sh` at your fork.** Change the default `DOTFILES_REPO` near the top of `install.sh`, or invoke with `DOTFILES_REPO=https://github.com/<you>/dotfiles.git bash install.sh`.
2. **Fill in `Brewfile.work`** with your employer's relevant apps (Slack, Zoom, Postman, JetBrains IDEs, …). Or empty it out entirely — it's allowed to be empty.
3. **Edit `Brewfile.personal`** to match your "personal machine" preferences.
4. **Tune the boundary between Brew and Devbox.** Keep workstation tools in Brewfiles; put project runtimes and CLIs in `examples/devbox/` templates or directly in each project's `devbox.json`.
5. **Replace `dot_config/claude/personal/CLAUDE.md` and `dot_codex/AGENTS.md`** with your own preferences. They currently encode my style; almost certainly not yours.
6. **Adjust `dot_config/git/config.tmpl`** if you don't want commit signing — the `[gpg "ssh"] program = …` block assumes 1Password's `op-ssh-sign`. The wizard's `useOnePassword` toggle controls whether the block renders.
7. **Re-render the README badges** — the CI badge URL hardcodes my GitHub handle.

Nothing in `install.sh` writes to the original `martinzachariassen` repo URL except the default for `DOTFILES_REPO`. As long as you replace that, every other personal value (name, email, signing key) comes from Phase B prompts and is stored locally in `~/.config/chezmoi/chezmoi.toml`, not in the source.

---

## Architecture

Three classes of files in this repo, plus chezmoi's own infrastructure.

**1. Files chezmoi writes to `$HOME`** — anything prefixed `dot_` (becomes `.X`), `private_dot_` (also enforces mode 0600). Templates end in `.tmpl` and get rendered with chezmoi's data at apply time. So `dot_config/git/config.tmpl` becomes `~/.config/git/config` with your name/email/signing key substituted in. `dot_config/zsh/dot_zshrc.tmpl` includes profile-conditional blocks rendered only when `{{ .profile }}` matches.

**2. Files chezmoi removes from `$HOME`** — `remove_*` markers are empty sentinels whose filename encodes a delete instruction. `remove_dot_gitconfig` ensures `~/.gitconfig` doesn't exist (because git checks `~/.gitconfig` *before* `~/.config/git/config` and would silently shadow our XDG-managed config). `remove_dot_zshrc` and `remove_dot_zprofile` defend the `ZDOTDIR`-based zsh layout. `remove_dot_bash_profile`, `remove_dot_bashrc`, and `remove_dot_profile` keep old bash/POSIX login hooks from accumulating stale bootstrap code in `$HOME`.

**3. Files chezmoi ignores entirely** — listed in `.chezmoiignore`. Repo metadata (`README.md`, `MAPPING.md`, `WORK-SETUP.md`, `LICENSE`), the install scripts (`install.sh`, `doctor.sh`, `bootstrap-auth.sh`, `macos-defaults.sh`), every `Brewfile*` (the brew-bundle chezmoi script consumes them directly, not through chezmoi's home-state), CI (`.github/`), formatters (`.editorconfig`, `.gitattributes`), examples (`examples/`), git's own files.

**chezmoi infrastructure**:

- `.chezmoi.toml.tmpl` — init prompts. Renders to `~/.config/chezmoi/chezmoi.toml` on `chezmoi init`.
- `.chezmoiscripts/` — auto-run hooks. Four user-visible steps per apply, in order:

  | # | Script | Phase | Runs when | What it does |
  |---|---|---|---|---|
  | 1 | `run_before_00-sudo-cache` | before, every apply | always | Pre-authenticates sudo on a clean terminal + background keeper refreshing every 50s. Silent no-op when sudo is already cached or there's no TTY. |
  | — | `run_once_before_01-install-homebrew` | before, once | first apply only | Installs Homebrew if missing. Silent on every subsequent apply. |
  | 2 | `run_onchange_before_01b-install-devbox` | before, on script change | always (idempotent) | Two-part: curl-installs devbox CLI from Jetify if missing, then bootstraps the Nix store at `/nix` via the Determinate Systems installer (`--determinate --no-confirm`). Both halves short-circuit when already present. |
  | 3 | `run_onchange_after_02-brew-bundle` | after, on Brewfile/profile/feature change | always | Layers core Brewfile + enabled workstation extras + your profile's extras. `exec </dev/tty` so sudo-requiring casks (docker-desktop, 1password) can read the password. Heartbeat every 45s during silent stretches. |
  | 4 | `run_once_after_04-macos-defaults` | after, once | first apply only | Runs `macos-defaults.sh`. Never re-fires automatically — re-apply edits via the `macos-defaults` zsh alias. |
  | — | `run_onchange_after_99-completion` | after, every apply | always | Prints the `✓ chezmoi apply complete` banner with the day-to-day reference card. Re-fires because the rendered content embeds `{{ now.Unix }}`. |

  The "step N/4" prefixes you see in apply output (`[brew-bundle] apply step 3/4 …`) match this numbering, so a wall of brew-bundle output never leaves you wondering what's left.

---

## Troubleshooting

If `chezmoi apply` ever prompts you about a file in `$HOME` having changed, the safest answer is `d` (diff) → look at it → then `o` (overwrite) if the changes don't matter, or `m` (merge) if they do.

A few specific issues worth knowing about:

**`./install.sh: permission denied`** — run it as `bash install.sh` instead, or `chmod +x install.sh` first. To make the bit stick across clones: `git update-index --chmod=+x install.sh && git commit`.

**The sudo password prompt during `chezmoi apply` gets eaten, treated as a command, or "doesn't work the first time"** — fixed at the chezmoi level: a `run_before_00-sudo-cache` script now runs at the very start of every apply (regardless of whether you invoked it via `chez`, `chezup`, or plain `chezmoi apply -v`). It prompts for sudo *once*, on a clean terminal, before brew bundle or any other heavy output starts. A background keeper refreshes the credentials every 50s for the duration of the apply, so every subsequent sudo call inside cask installs and macos-defaults runs silently — even if brew bundle takes 20 minutes.

You'll see something like:

```text
── Sudo pre-authentication ───────────────────────────────────────
  A few scripts in this apply need sudo (cask installs, macOS
  defaults). Entering your password here — once, on a clean
  terminal — caches it for the rest of the apply…
──────────────────────────────────────────────────────────────────
[chezmoi] sudo password:
```

The distinct `[chezmoi] sudo password:` prompt is intentional — it's the visual signal to *stop typing* until you see it. On GPU-accelerated terminals (Ghostty, Alacritty, Kitty) keystrokes can arrive faster than sudo's TTY mode switch from echo-on to echo-off, eating the first character. A brief settle pause before the prompt closes that race.

If sudo is already cached when apply runs (recent `sudo` command in the same 5-min window), the pre-auth script is a silent no-op — you only get prompted when you actually need to be.

To pick up this fix on an existing machine: `chezup` once, then re-run `chezmoi apply -v`. (Or just run the wizard again: `bash ~/Dev/Personal/dotfiles/install.sh`.)

Why this used to happen: chezmoi runs scripts with stdin disconnected by default. Casks like docker-desktop and 1password invoke sudo as part of their install; with stdin closed, sudo's password prompt fires but characters typed at the keyboard end up at the parent shell. Defence in depth: every script that might trigger sudo now does `exec </dev/tty` on entry to re-attach stdin, the pre-auth script prompts once on a clean terminal upfront, and `macos-defaults.sh` standalone-use also gets a settle pause + distinct prompt for the case when you run it via the `macos-defaults` alias outside of chezmoi.

**Brew bundle fails: `Error: It seems there is already a Binary at '/opt/homebrew/bin/claude'`** — another Claude Code cask is already installed. This repo tracks `claude-code` in the work profile only; uninstall any conflicting Claude Code cask and apply again.

**`chezmoi apply` seems to halt after the completion banner** — almost always a leftover sudo-keeper. The current code uses a double-fork detach + 2-second poll interval, so the keeper exits within 2 seconds of chezmoi finishing. If you're on a version from before that fix and see a halt: `pgrep -f "sudo -n true"` will show any orphaned keepers; `pkill -f "sudo -n true"` cleans them up. Run `chezup` once to pull the fix so it doesn't happen again.

**`chezmoi apply -v` floods the terminal with per-file content diffs** — that's `-v` doing exactly what it's documented to do: print the contents of every change. For daily use you don't want that; use `chez` instead, which calls `chezmoi apply --force` (no `-v`). Your scripts (brew progress, sudo-cache, completion summary) still produce their normal output — only chezmoi's per-file content dumps are suppressed.

```sh
chez              # quiet apply (recommended daily)
chez -v           # opt back into verbose if you're debugging
chezmoi apply     # also quiet (now that --force is the default via .chezmoi.toml)
```

**`chezmoi apply` drops you into a `diff/overwrite/skip/quit/merge` prompt mid-apply** — that's chezmoi's per-file drift resolver, fired when a managed file in `$HOME` has been changed locally. Fixed by `[apply] force = true` in `.chezmoi.toml.tmpl`. **Existing installs need to re-init to pick this up:**

```sh
chezreinit       # pulls + re-runs chezmoi init + applies
```

After that, plain `chezmoi apply` overwrites local drift without asking. The safety net is `chez` — status preview + one-shot confirmation. If you actually want to *keep* a local edit to a managed file, run `chezmoi re-add ~/.X` first to capture it back into source.

Escape hotkeys for the legacy prompt if you ever hit it: `q` quits the whole apply, `s` skips just this file, `a` applies all remaining without further prompts.

**`chezmoi diff` / `git log` / `git diff` traps you in a pager and you don't know how to escape** — `~/.zshenv` configures `less` with flags that make this painless:

```sh
LESS='-FRK -P"Press q or Ctrl-C to quit · / search · h for help"'
```

What each flag does:

| Flag | Effect |
|---|---|
| `-F` | Auto-quit when output fits in one screen — you go straight back to the prompt with nothing to dismiss |
| `-R` | Pass ANSI color codes through, so delta's syntax highlighting renders |
| `-K` | **Ctrl-C exits less** instead of just interrupting the current search |
| `-P…` | Show a visible status line: `Press q or Ctrl-C to quit · / search · h for help` instead of the cryptic default `:` |

Note the deliberate omission of `-X` (no-terminal-init). With `-X`, less prints to your normal terminal stream — which means the "Press q…" status line sticks around in your scrollback as a stale artifact every time less auto-quits. Without `-X`, less uses the alternate-screen buffer: content and prompt vanish cleanly on exit, leaving your terminal exactly as it was before the pager opened. To re-view a diff, just re-run the command.

Delta's `pager = "less -FRK -P'…'"` in `~/.config/git/config` is the belt-and-braces complement in case `LESS` is unset somewhere upstream.

After this lands you have three independent ways to escape any pager:

- **q** — quit (works in all `less` versions)
- **Ctrl-C** — quit (works because of `-K`)
- **(implicit)** short diffs auto-exit, no key needed

For long-page operations you didn't want, override per-call:

```sh
chezmoi diff | cat                 # pipe past the pager entirely
GIT_PAGER=cat git diff             # one-shot pager override
LESS=-RX chezmoi diff              # one-shot less override (always pages, no -F)
```

**Brew bundle looks frozen — no output for minutes** — long downloads (large casks, slow networks) can sit silently because brew streams output only as steps complete. The brew-bundle script now prints a heartbeat every 45 seconds during silent stretches:

```text
[brew-bundle] ┌── 1/7  core (always)  (Brewfile)
...brew bundle output...
[brew-bundle]   … still working on core (always) — 1m30s elapsed
[brew-bundle]   … still working on core (always) — 2m15s elapsed
[brew-bundle] └── ✓ 1/7  core (always)  done in 2m48s
```

Plus an upfront plan that tells you what's coming and roughly how long:

```text
═════════════════════════════════════════════════════════════════════
[brew-bundle] apply step 3/4 — installing/updating brew packages
[brew-bundle] modules to apply: 4
[brew-bundle]   1. core (always)
[brew-bundle]   2. mac apps (Rectangle/Raycast/Stats/Chrome/dive)
[brew-bundle]   3. personal profile extras
[brew-bundle]   4. work profile extras
[brew-bundle] expected time on first install: ~5-15 min (downloads dominate)
═════════════════════════════════════════════════════════════════════
```

If you genuinely think brew is frozen (heartbeat stopped firing too), `ps aux | grep brew` will show whether brew is still working — most often it's stuck on a `curl` for a slow mirror.

**`chezmoi apply -v` hangs at `tightening permissions on /opt/homebrew/share/zsh*`** — should finish in <1s now (scoped to just the zsh dirs). If it hangs longer, you're probably running an old version of the script — Ctrl-C, `git pull` (or just re-run `chezmoi apply` from the source dir), and re-apply.

**Old `chezmoi apply` runs prompted about `.zsh_history`** — this used to fight with an active shell because `remove_dot_zsh_history` markers tried to delete a file the shell kept recreating. Those markers are gone. If you still have the legacy files (`~/.zsh_history` or `~/.config/zsh/.zsh_history`), delete them once: `rm -f ~/.zsh_history ~/.config/zsh/.zsh_history`.

---

## Uninstall / reset

For the supported "make Homebrew match the managed workstation set" flow, run:

```sh
bash ~/Dev/Personal/dotfiles/install.sh --mirror-brew
bash ~/Dev/Personal/dotfiles/install.sh --reset-brew
```

`--mirror-brew` leaves the Homebrew installation in place and removes formulae/casks that are not listed in the active Brewfile set for your selected profile/features. `--reset-brew` removes all current formulae/casks first, then reinstalls whatever the selected profile/features require. Both are intentionally guarded by an explicit confirmation phrase in interactive mode.

There's no `uninstall.sh` because there's not a clean inverse — the bootstrap installs ~55 brew packages, modifies macOS defaults, and changes your shell's interpretation of `$HOME`. If you want to walk it back, the steps are:

```sh
# 1. Stop chezmoi managing your $HOME (drops the source link, leaves $HOME files in place).
chezmoi purge                                                # interactive; removes ~/.config/chezmoi/

# 2. Remove every brew package this repo installed. The two-step form below
#    keeps tools you've added on top.
brew bundle cleanup --force --file=~/Dev/Personal/dotfiles/Brewfile
brew bundle cleanup --force --file=~/Dev/Personal/dotfiles/Brewfile.personal
brew bundle cleanup --force --file=~/Dev/Personal/dotfiles/Brewfile.work

# 3. Restore from the pre-install backup (install.sh writes one before its first apply).
ls ~/.dotfiles-backup-*                                      # find the snapshot
cp -r ~/.dotfiles-backup-<timestamp>/. ~/                    # restore

# 4. Remove the source repo if you don't want to keep it.
rm -rf ~/Dev/Personal/dotfiles
```

macOS system defaults applied by `macos-defaults.sh` aren't reverted by the above — they're sticky settings you'd toggle back via *System Settings* (or by writing inverse `defaults write` commands). The Touch ID for sudo line in `/etc/pam.d/sudo_local` can be removed with `sudo rm /etc/pam.d/sudo_local` (keeps Apple's `sudo_local.template` intact).

The `~/.dotfiles-backup-*` directories accumulate — one per install run. After verifying you don't need them, `rm -rf ~/.dotfiles-backup-*`.

---

## Reference

- [`MAPPING.md`](MAPPING.md) — every file in the repo and where it lands in `$HOME`, plus chezmoi internals.
- [`WORK-SETUP.md`](WORK-SETUP.md) — corporate Claude Code (`storecode`) install, separate from this repo.
- [`install.sh`](install.sh) — the 6-phase wizard (fresh + existing Macs). `DRY_RUN=1` previews, `YES=1` accepts defaults.
- [`bootstrap-auth.sh`](bootstrap-auth.sh) — post-install gh / az / gcloud / AKS / GKE / signing walkthrough. Idempotent.
- [`doctor.sh`](doctor.sh) — read-only health check. Aliased as `chezdoctor`.
- [`Brewfile`](Brewfile) — core, always installed. [`Brewfile.mac-apps`](Brewfile.mac-apps) is the optional workstation feature. Profile-specific extras: [`Brewfile.personal`](Brewfile.personal), [`Brewfile.work`](Brewfile.work).
- [`examples/`](examples/) — drop-in starter files for `direnv`, `pre-commit`, and Devbox project templates.
- [`.github/workflows/ci.yml`](.github/workflows/ci.yml) — shellcheck + chezmoi template-render + macOS brew-bundle check on every PR.

---

## License

MIT — see [`LICENSE`](LICENSE). Copy what's useful, discard what isn't. It's just my dotfiles.
