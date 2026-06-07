# Bootstrap

On a fresh Mac, open any terminal and run:

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

Run that command as your normal macOS user, not with `sudo`. `sudo curl ... | bash` only makes the download privileged, not the installer. `curl ... | sudo bash` runs the whole setup as root, which breaks Homebrew and writes dotfiles into the wrong home directory. The installer and Homebrew will ask for your sudo password at the specific steps that need it.

You'll meet a guided terminal wizard themed to match the rest of the setup (Catppuccin Frappé), with a framed banner, per-step progress bars, an animated spinner for long steps, and **arrow-key menus** (↑/↓ + Enter, or press the number). It adapts to the terminal it runs in: truecolor → 256-color → 16-color → no-color, Unicode glyphs → ASCII, and arrow-key menus → numbered entry. Anything without an interactive terminal — `curl | bash` pipes, CI, `YES=1` — automatically falls back to numbered/auto-accepted prompts and log-friendly heartbeats instead of the spinner. It works the same in Ghostty, Terminal.app, iTerm, SSH, and stock macOS bash 3.2.

The default path is aimed at a fresh macOS install: it asks only for profile, git name, and git email. It does not ask for a 1Password signing public key before 1Password exists on the machine. Git signing is finished by `bootstrap-auth.sh` after 1Password is installed and signed in. Package cleanup, feature toggles, and manual signing-key entry live behind the customize option.

Once you confirm, the install runs unattended except for system prompts such as Xcode CLT or sudo. Total time is usually ~15 min, almost all of it Apple tooling and Homebrew downloading. On a fresh Mac, the first install stage prints its own sub-plan and heartbeat around Xcode CLT, Homebrew, chezmoi, and the repo clone. The later Homebrew package stage is split into individual taps/formulae/casks with per-item timing and a 30-second heartbeat during quiet downloads, so a rerun can resume through Homebrew's normal "already installed" checks instead of repeating the whole package set.

```text
╭──────────────────────────────────────────────────────────╮
│ ◆ DOTFILES                                               │
│ macOS workstation setup                                  │
│ catppuccin frappe · truecolor                            │
╰──────────────────────────────────────────────────────────╯
│  The default path only asks for inputs available on a fresh Mac.
│  Git signing is finished later, after 1Password is installed and signed in.
│  Advanced cleanup and feature toggles stay available when you need them.
│
◆  Step 2/5   ▰▰▰▰▱▱▱▱▱▱▱▱ 40%
│  Choose setup
│
│  Essentials first. Press Enter keeps the detected value.
│      Fresh installs only need profile, git name, and git email here.
│
◆  Profile  → ↑/↓ Enter
│    ❯ ● personal — personal extras only
│      ○ work     — work extras only
│
│  Recommended setup
│    1Password          yes
│    Git signing        finish later in bootstrap-auth.sh
│    Mac apps           yes
│    Homebrew cleanup   keep local packages
◆  Setup style  → ↑/↓ Enter
│    ❯ ● Continue with recommended setup
│      ○ Customize packages, signing, cleanup, and migration
```

When the terminal has no interactive keyboard (pipes, CI), the same screens render in plain ASCII with numbered entry instead — e.g. `1. personal …` / `Choose 1-2`.

The wizard is idempotent. Re-run it any time — it detects existing state, shows current values as defaults, lets you change profile/identity/features, and skips steps that are already done.

Useful environment variables:

```sh
DRY_RUN=1         bash install.sh   # print state-changing commands without running them
YES=1             bash install.sh   # accept recommended defaults at every prompt (good for CI / reinstalls)
SKIP_BACKUP=1     bash install.sh   # don't snapshot pre-existing legacy dotfiles
DOTFILES_REPO=…   bash install.sh   # point at a fork
DOTFILES_DIR=…    bash install.sh   # clone somewhere other than ~/Developer/personal/dotfiles
```

For a Homebrew cleanup, there are two guarded modes:

```sh
bash install.sh --mirror-brew  # remove packages not in the active Brewfiles
bash install.sh --reset-brew   # uninstall everything first, then reinstall
```

Mirror mode keeps packages from the active set: `Brewfile`, enabled feature Brewfiles such as `brewfiles/Brewfile.mac-apps`, and the selected profile Brewfile(s). It removes local Homebrew packages outside that set. Reset mode uninstalls every current Homebrew formula and cask, then lets `chezmoi apply` reinstall the repo-managed set. In interactive runs you must type `MIRROR BREW` or `RESET BREW` before the cleanup proceeds.

On an already-bootstrapped machine, use the short configuration path when you
only want to change profile, identity, or feature toggles:

```sh
bash install.sh --configure-only
```

### The install flow

| Phase | Name | What it does |
|---|---|---|
| **1/5** | Check this Mac | Read-only probe of macOS version + arch, Xcode CLT, Homebrew, chezmoi, existing repo clone, prior chezmoi config, 1Password.app, and legacy files (`~/.zshrc`, `~/.gitconfig`, oh-my-zsh, …). Nothing changes here. |
| **2/5** | Choose setup | Essentials first: profile, name, and email. Existing signing keys are preserved, but fresh installs leave signing for the post-install auth step because the key comes from 1Password. The recommended path keeps 1Password enabled, installs macOS app extras, leaves local Homebrew packages alone, backs up legacy dotfiles, and removes oh-my-zsh if found. Choose customize to change signing, feature toggles, Homebrew mirror/reset, or migration behavior. |
| **3/5** | Review plan | One-screen summary of every choice. Last chance to abort. Destructive Homebrew cleanup modes require typing `MIRROR BREW` or `RESET BREW`. |
| **4/5** | Install and apply | Shows a fresh-Mac sub-plan, backs up legacy files (to `~/.dotfiles-backup-<timestamp>/`), optionally resets Homebrew, installs Xcode CLT (polls the GUI dialog up to 60 min), Homebrew, chezmoi, clones the repo, runs `chezmoi init` with all answers pre-supplied (zero prompts), then `chezmoi apply` — which installs Homebrew packages once in a split per-item progress view, applies dotfiles, installs VS Code extensions, and runs macOS defaults (sudo once). Long external installers print a 30-second heartbeat. |
| **5/5** | Verify | Functional checks for the workstation baseline. Reports auth state for `gh`/`az`/`gcloud` as FYI when those tools are present. |
| **Next steps** | Finish accounts | Prints the exact follow-ups: sign in to 1Password, run `bootstrap-auth.sh`, `exec zsh`, restart. |

After the wizard finishes:

```sh
# 1. Sign in to 1Password (so SSH agent + git signing work) — skip if disabled in customize
open -a 1Password

# 2. Walk through account auth. Azure/GCP steps are skipped unless those CLIs are installed.
bash ~/Developer/personal/dotfiles/scripts/bootstrap-auth.sh

# 3. Reload shell with the new config
exec zsh

# 4. Restart the Mac so all macOS defaults take full effect
sudo shutdown -r now
```

### Profiles & features

The setup screen asks two orthogonal questions: which **profile** you're on (which casks/aliases get layered in) and, when you choose customize, which workstation **extras** you want globally.

**Profile** controls personal-vs-work cask + shell-config layering:

| Profile | Brewfiles applied (on top of core) | Notes |
|---|---|---|
| `personal` | `brewfiles/Brewfile.personal` | Personal-only apps you add. Personal-only `.zshrc` block renders. |
| `work` | `brewfiles/Brewfile.work` | Work-only apps you add (Slack, Teams, Postman, etc.). Work-only `.zshrc` block renders. |

**Features** are intentionally narrow. Project language runtimes are mise-owned; Homebrew features are only for workstation-level preferences:

| Feature | Brewfile | What's in it |
|---|---|---|
| `macApps` | `brewfiles/Brewfile.mac-apps` | Raycast, Stats, Chrome, and other GUI quality-of-life apps, plus AI tooling: Ollama (local model runner) and the Claude and Claude Code apps. `scripts/setup-ollama.sh` starts Ollama as a brew service; models are pulled manually via `ollama pull` because they are large. Skip on a server-y machine. |

The core `Brewfile` always installs the workstation baseline: git, GitHub CLI, modern CLI, prompt, zsh tooling, Ghostty, VS Code, 1Password GUI + CLI, Docker Desktop, Nerd Fonts, Neovim, `mise`, and other shell primitives. Azure and Google Cloud account CLIs live in the work profile (`brewfiles/Brewfile.work`) and are installed when the selected profile is `work`. Project Kubernetes tools, Terraform/OpenTofu, and database clients/servers stay in Homebrew or run via Docker; per-project language runtimes belong in each project's `mise.toml`. Starter templates live under [`examples/mise/`](../examples/mise/).

Raycast config is backed up through Raycast's encrypted `.rayconfig` export format rather than a live dotfile. After Raycast is installed, open *Raycast Settings → Advanced → Export*, set an export passphrase stored in 1Password, and use [`raycast/`](../raycast/) as the scheduled backup location. On a new Mac, run Raycast's `Import Settings & Data` command and choose the latest export from that folder.

To flip a profile or feature later:

```sh
dotfiles profile set work
dotfiles profile set personal
dotfiles features list
dotfiles features disable macApps
dotfiles features enable macApps
dotfiles signing set
```

`dotfiles` with no arguments still jumps to the source repo. With arguments it
updates `~/.config/chezmoi/chezmoi.toml` and applies the affected managed files.

### Day-one secrets and signing

The bootstrap pulls config and tools, but **secrets aren't in this repo on purpose**. Here's where they actually come from on a fresh Mac.

**SSH keys** — both authentication and git signing use the **1Password SSH agent**, not files on disk. Once you sign in to 1Password and enable *Settings → Developer → SSH agent*, every SSH key in your vault becomes available to `ssh`, `git`, and anything else that talks to `$SSH_AUTH_SOCK`. There are no `~/.ssh/id_*` private keys to copy across machines — that's the whole point. Public keys for known_hosts you'll have to accept once per host.

**Git commit signing** — the private key never leaves 1Password; `op-ssh-sign` (bundled with the 1Password macOS app) signs commits via the agent. If the public signing key is known during install, chezmoi renders signing immediately. On a fresh Mac it usually is not known yet, so `bootstrap-auth.sh` prompts for the public key after 1Password is installed and signed in, writes it to chezmoi data, reapplies `dot_config/git/config.tmpl`, and runs a `git -S` smoke test against an empty repo. The template also writes `~/.config/git/allowed_signers` so local SSH signature verification works.

**Cloud auth tokens** — `gh`, `az`, and `gcloud` each store their own credentials under `~/.config/gh/`, `~/.azure/`, `~/.config/gcloud/`. GitHub CLI is part of the core setup. Azure and Google Cloud CLIs are extras for the `work` profile because not every personal Mac needs cloud account tooling. Project CLIs stay in Homebrew or Docker. `bootstrap-auth.sh` walks through whichever CLIs are installed and skips the rest. None of these directories are tracked in this repo.

**1Password CLI** (`op`) — separate from the GUI sign-in. First run on a machine: `op account add` (paste account URL + secret key), then `eval $(op signin)`. Subsequent shell sessions: `eval $(op signin)`.

### Privacy permissions checklist

macOS won't let any script grant Privacy permissions; you have to click them in *System Settings → Privacy & Security*. None of these break on day one but several of your tools silently won't work right until granted. The checklist:

- **Full Disk Access** → your terminal (Ghostty). Useful for `find` operations against protected dirs.
- **Accessibility** → Rectangle, Raycast, and Karabiner-Elements (if you use it). Without this, Rectangle can't move windows and Raycast can't simulate keystrokes.
- **Screen Recording** → Raycast (for screenshot features), and any screenshot/screen-share tools.
- **Input Monitoring** → Karabiner-Elements (if used). Without it, Karabiner can't see your keystrokes.
- **Developer Tools** → your terminal. Reduces Gatekeeper friction when running locally-built binaries.
- **Automation** → grant your terminal the right to control whichever apps you script via `osascript`.

Run `chezdoctor` for a reminder. The script can't verify these for you, but it prints the list at the end.
