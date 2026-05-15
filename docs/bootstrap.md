# Bootstrap

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

### The six phases

| Phase | Name | What it does |
|---|---|---|
| **A** | Discovery | Read-only probe of macOS version + arch, Xcode CLT, Homebrew, chezmoi, existing repo clone, prior chezmoi config, 1Password.app, and legacy files (`~/.zshrc`, `~/.gitconfig`, oh-my-zsh, …). Nothing changes here. |
| **B** | Choices | Numbered profile picker. Identity text fields with existing values as defaults. 1Password yes/no; if yes, paste the public signing key. Workstation extras such as local AI tooling and macOS quality-of-life apps. Existing-system handling (Homebrew mirror/reset? back up + remove legacy files? uninstall oh-my-zsh?). |
| **C** | Confirm | One-screen summary of every choice. Last chance to abort. |
| **D** | Execute | Backs up legacy files (to `~/.dotfiles-backup-<timestamp>/`), optionally resets Homebrew, installs Xcode CLT (polls the GUI dialog up to 20 min), Homebrew, chezmoi, clones the repo, runs `chezmoi init` with all answers pre-supplied (zero prompts), then `chezmoi apply` — which fans out to `brew bundle` against core + workstation/profile extras, plus macOS defaults (sudo once). |
| **E** | Self-test | Functional checks for the workstation baseline. Reports auth state for `gh`/`az`/`gcloud` as FYI when those tools are present. |
| **F** | Next steps | Prints the exact follow-ups: sign in to 1Password, run `bootstrap-auth.sh`, `exec zsh`, restart. |

After the wizard finishes:

```sh
# 1. Sign in to 1Password (so SSH agent + git signing work) — skip if you said no in Phase B
open -a 1Password

# 2. Walk through CLI auth (gh, az, gcloud, AKS/GKE plugins, signing test). Idempotent.
bash ~/Developer/personal/dotfiles/scripts/bootstrap-auth.sh

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
| `personal` | `brewfiles/Brewfile.personal` | Personal-only apps you add. Personal-only `.zshrc` block renders. |
| `work` | `brewfiles/Brewfile.work` | Work-only apps you add (Slack, Teams, Postman, etc.). Work-only `.zshrc` block renders. |
| `both` | both | Single-machine-many-jobs. |

**Features** are intentionally narrow. Project toolchains are Devbox-owned; Homebrew features are only for workstation-level preferences:

| Feature | Brewfile | What's in it |
|---|---|---|
| `ai` | `brewfiles/Brewfile.ai` | Ollama + `llm` for local model runs and shell-pipeline prompts. Model downloads are manual via `scripts/setup-local-llm.sh` because they are large. |
| `macApps` | `brewfiles/Brewfile.mac-apps` | Rectangle, Raycast, Stats, Chrome, dive. Pure QoL — skip on a server-y machine. |

The core `Brewfile` always installs the workstation baseline: git, modern CLI, prompt, zsh tooling, Ghostty, VS Code, 1Password GUI + CLI, Docker Desktop, Nerd Fonts, Neovim, `direnv`, `az`, `gcloud`, and other shell primitives. Project-pinned Kubernetes tools, Terraform/OpenTofu, database clients/servers, and language runtimes belong in each project's `devbox.json`. Starter templates live under [`examples/devbox/`](../examples/devbox/).

Raycast config is backed up through Raycast's encrypted `.rayconfig` export format rather than a live dotfile. After Raycast is installed, open *Raycast Settings → Advanced → Export*, set an export passphrase stored in 1Password, and use [`raycast/`](../raycast/) as the scheduled backup location. On a new Mac, run Raycast's `Import Settings & Data` command and choose the latest export from that folder.

To flip a profile or feature later:

```sh
dotfiles profile set work
dotfiles profile set personal
dotfiles features list
dotfiles features enable ai
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

- **Full Disk Access** → your terminal (Ghostty). Useful for `find` operations against protected dirs.
- **Accessibility** → Rectangle, Raycast, and Karabiner-Elements (if you use it). Without this, Rectangle can't move windows and Raycast can't simulate keystrokes.
- **Screen Recording** → Raycast (for screenshot features), and any screenshot/screen-share tools.
- **Input Monitoring** → Karabiner-Elements (if used). Without it, Karabiner can't see your keystrokes.
- **Developer Tools** → your terminal. Reduces Gatekeeper friction when running locally-built binaries.
- **Automation** → grant your terminal the right to control whichever apps you script via `osascript`.

Run `chezdoctor` for a reminder. The script can't verify these for you, but it prints the list at the end.
