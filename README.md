# dotfiles

[![CI](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/martinzachariassen/dotfiles/actions/workflows/ci.yml)
[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Managed by chezmoi](https://img.shields.io/badge/managed%20by-chezmoi-66ccff)](https://chezmoi.io)
[![Catppuccin Frappé](https://img.shields.io/badge/Catppuccin-Frapp%C3%A9-f2d5cf?labelColor=303446)](https://github.com/catppuccin/catppuccin)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> Personal macOS setup, managed by [chezmoi](https://chezmoi.io). One command bootstraps a fresh Mac into a fully configured backend dev environment — terminal, multiplexer, prompt, editors, runtimes, cloud + Kubernetes tooling, and macOS system defaults all in their final state.

## Table of Contents

- [Bootstrap](#bootstrap)
  - [Profiles](#profiles)
- [What you get](#what-you-get)
  - [What the prompt looks like](#what-the-prompt-looks-like)
- [Day-to-day](#day-to-day)
  - [Mental model: source → `$HOME`](#mental-model-source--home)
  - [Adding a new tool](#adding-a-new-tool)
  - [Previewing changes before applying](#previewing-changes-before-applying)
  - [Shell aliases & shortcuts](#shell-aliases--shortcuts)
- [Claude Code: work vs personal](#claude-code-work-vs-personal)
- [Architecture](#architecture)
- [Troubleshooting](#troubleshooting)
- [Reference](#reference)
- [License](#license)

---

## Bootstrap

On a fresh Mac, open Terminal and run:

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

The script is a guided 8-step tour with a banner up top and clear, color-coded progress through each step. It's idempotent — re-running is safe. Total time: ~15–20 minutes (mostly Homebrew downloading).

The 8 steps:

1. **Xcode Command Line Tools** — a GUI dialog appears the first time. Click *Install*, wait for it to finish, then re-run the script (it exits with a hint).
2. **Homebrew** — installed non-interactively at the Apple Silicon path (`/opt/homebrew`).
3. **chezmoi** — installed via `brew install chezmoi`.
4. **Clone repo** to `~/Dev/Personal/dotfiles` (over HTTPS, so a fresh Mac with no SSH agent can authenticate).
5. **Configure chezmoi** — prompts for **profile** (personal / work / both) and **identity** (name, git email, SSH signing public key from your 1Password entry). Answers stored in `~/.config/chezmoi/chezmoi.toml`; persist across re-runs.
6. **Apply dotfiles + install packages** — writes every dotfile, then runs `brew bundle` against the appropriate Brewfiles for your profile, installs VS Code extensions, applies macOS system defaults (sudo prompt — once).
7. **Re-render config** — re-runs `chezmoi init` so the `[diff] pager = "delta"` block in the rendered config picks up the now-installed `delta` (which only exists on PATH after step 6).
8. **Self-test** — verifies key tools and apps (`git`, `chezmoi`, `mise`, `starship`, `zellij`, `kubectl`, `lazygit`, `direnv`, `claude`, plus Ghostty/VS Code/1Password apps) actually landed.

When it's done, do these in order:

```sh
# 1. Sign in to 1Password (so SSH agent + git signing work)
open -a 1Password

# 2. Authenticate cloud CLIs
gh auth login            # GitHub
gcloud auth login        # GCP — optional

# 3. Reload shell with the new config
exec zsh

# 4. Restart the Mac so all macOS defaults take full effect
sudo shutdown -r now
```

### Profiles

The `profile` answer at step 5 controls which packages and shell config get installed:

| Profile | What you get |
|---|---|
| `personal` | Common `Brewfile` + `Brewfile.personal` (Claude desktop + Claude Code CLI cask, plus any other personal-only apps you add). Personal-only `.zshrc` block renders. |
| `work` | Common `Brewfile` + `Brewfile.work` (work-only apps you add — Slack, Teams, Postman, etc.). Work-only `.zshrc` block renders, including `~/.storecode/bin` on PATH if installed. Personal Claude casks are *not* installed (work uses storecode-managed `~/.claude` per [`WORK-SETUP.md`](WORK-SETUP.md)). |
| `both` | Common `Brewfile` + both extras + both `.zshrc` blocks. Useful for a single-machine-many-jobs setup. |

The brew-bundle chezmoi script reads `{{ .profile }}` from chezmoi's data context and layers the right extras on top of the common Brewfile.

To switch profiles later, edit `~/.config/chezmoi/chezmoi.toml` and change `profile = "..."`, then `chezmoi apply -v`. The new profile's extras get installed automatically; the old profile's packages stay (manually `brew uninstall <name>` if you want to clean up).

---

## What you get

| Area | What's in the box |
|---|---|
| **Terminal** | [Ghostty](https://ghostty.org) with Catppuccin Frappé, JetBrainsMono Nerd Font, transparent titlebar, blurred background. Theme YAML at `~/.config/ghostty/themes/catppuccin-frappe` (chezmoi-managed, so it's deterministic across Ghostty versions). |
| **Multiplexer** | [Zellij](https://zellij.dev) with the Catppuccin Frappé theme, compact layout, mouse + clipboard integration, session persistence. Launch with the `zj` alias. Auto-attach on shell startup is opt-in (commented snippet in `.zshrc`). |
| **Prompt** | [Starship](https://starship.rs) with Catppuccin Frappé palette. Two-line prompt that surfaces git branch/status, language versions (Java/Node/Python/Go), Kubernetes context, and AWS profile only when contextually relevant — keeps it clean otherwise. See [the prompt examples](#what-the-prompt-looks-like) below. |
| **Shell** | zsh with full XDG layout, mise activation, direnv hook, fzf integration (`Ctrl-R` history search, `**<Tab>` completion), `zsh-completions` + `zsh-syntax-highlighting`, claude work/personal wrapper, modern CLI aliases (`ls→eza`, `cat→bat`, `find→fd`). |
| **Git** | Identity + 1Password commit signing via `op-ssh-sign`, delta diffs, useful aliases (`s`, `lg`, `wip`, `undo`, `amend`, `fixup`), pull rebase, rerere. |
| **Runtimes** | mise: Java 21 (Temurin), Maven, Gradle, Node (bundles npm), pnpm, Python — all "latest", overridable per-project via `.mise.toml`. |
| **Brew** | ~55 packages (common tier) + per-profile extras. Full list with one-line rationale per package in [`Brewfile`](Brewfile). Categories: modern CLI, git productivity (`lazygit`, `pre-commit`, `direnv`), Kubernetes (`kubectx`, `stern`, `k9s`), cloud + IaC (`awscli`, `gcloud-cli`, `opentofu`, `tflint`), DB clients (`pgcli`, `mysql-client`, `redis-cli`), container introspection (`dive`), backend HTTP/RPC (`grpcurl`, `mkcert`), plus the GUI app casks. |
| **Editor (GUI)** | VS Code with Catppuccin Frappé, Material Icon Theme, JetBrainsMono ligatures, Python + Pylance + black-formatter + Containers extensions, format on save. |
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

The `❯` prompt char turns red on a non-zero exit status. Language icons require a Nerd Font (JetBrainsMono Nerd Font, installed by the Brewfile and set in Ghostty + VS Code).

---

## Day-to-day

### Mental model: source → `$HOME`

`chezmoi apply` is **one-way**: it writes the source repo's files into `$HOME`, never the other direction. If you edit `~/.zshrc` directly with a text editor, the next `chezmoi apply` will either silently overwrite it (if it matches the last-known state) or prompt you to choose (if it's diverged).

The mental model that prevents accidents:

```sh
chezmoi edit ~/.zshrc            # opens the SOURCE file in $EDITOR (the right way)
chezmoi diff                     # preview what would change in $HOME
chezmoi apply -v                 # write changes
chezmoi update                   # git pull + chezmoi apply
```

If you accidentally edited a `$HOME` file directly and want to keep those changes, go the other direction:

```sh
chezmoi re-add ~/.zshrc          # captures live $HOME version back into source
chezmoi cd                       # cd to source repo
git diff                         # review
git add . && git commit -m "..."
```

### Adding a new tool

Two flavors, depending on whether you just want the binary or also a config file.

**Just the binary** — add it to the right Brewfile tier, commit, push:

```sh
dotfiles                                                   # cd ~/Dev/Personal/dotfiles
echo 'brew "httpx"' >> Brewfile                            # or Brewfile.personal / Brewfile.work
git add Brewfile && git commit -m "Add httpx" && git push
chezmoi apply -v                                            # triggers brew-bundle re-run via hash change
```

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

# Modern CLI replacements (only activate if the tool is installed)
ls, ll, tree                 # eza variants
cat                          # bat (use `command cat` or `\cat` to bypass)
find                         # fd

# Terminal multiplexer
zj                           # zellij attach -c default — named session, detach/reattach friendly

# Claude Code profile (also auto-routes by PWD)
cw                           # work profile      (CLAUDE_CONFIG_DIR=~/.claude)
cme                          # personal profile  (CLAUDE_CONFIG_DIR=~/.config/claude/personal)

# Maintenance ceremonies (run on demand, NOT on every chezmoi apply)
macos-defaults               # re-apply system settings (sudo prompt; idempotent)
```

---

## Claude Code: work vs personal

A wrapper function in `.zshrc` routes `claude` based on PWD:

- Anywhere under `~/Dev/Work/` → uses `~/.claude` (work profile, managed by employer's tooling — see [`WORK-SETUP.md`](WORK-SETUP.md))
- Everywhere else → uses `~/.config/claude/personal`

Override with `cw` (work) or `cme` (personal) aliases, or `CLAUDE_PROFILE=work claude …` for one-off.

The CLI binary comes from the `cask "claude-code@latest"` line in `Brewfile.personal` (rolling channel — auto-updates as Anthropic ships). Switch to `cask "claude-code"` if you'd rather pin to the stable named release.

---

## Architecture

Three classes of files in this repo, plus chezmoi's own infrastructure.

**1. Files chezmoi writes to `$HOME`** — anything prefixed `dot_` (becomes `.X`), `private_dot_` (also enforces mode 0600). Templates end in `.tmpl` and get rendered with chezmoi's data at apply time. So `dot_config/git/config.tmpl` becomes `~/.config/git/config` with your name/email/signing key substituted in. `dot_config/zsh/dot_zshrc.tmpl` includes profile-conditional blocks rendered only when `{{ .profile }}` matches.

**2. Files chezmoi removes from `$HOME`** — three `remove_*` markers (empty sentinels whose filename encodes a delete instruction). `remove_dot_gitconfig` ensures `~/.gitconfig` doesn't exist (because git checks `~/.gitconfig` *before* `~/.config/git/config` and would silently shadow our XDG-managed config). `remove_dot_zshrc` and `remove_dot_zprofile` defend the `ZDOTDIR`-based zsh layout against legacy files.

**3. Files chezmoi ignores entirely** — listed in `.chezmoiignore`. Repo metadata (`README.md`, `MAPPING.md`, `WORK-SETUP.md`, `LICENSE`), the install scripts (`install.sh`, `Brewfile*`, `macos-defaults.sh`), CI (`.github/`), formatters (`.editorconfig`, `.gitattributes`), examples (`examples/`), git's own files.

**chezmoi infrastructure**:

- `.chezmoi.toml.tmpl` — init prompts. Renders to `~/.config/chezmoi/chezmoi.toml` on `chezmoi init`.
- `.chezmoidata/packages.toml` — data file (vscode extension list) available in every template via `{{ .vscode.extensions }}`.
- `.chezmoiscripts/` — auto-run hooks. `run_once_before_*` runs once before the first apply (Homebrew install). `run_onchange_after_*` re-runs when content hash changes (brew bundle, vscode extensions). `run_once_after_*` runs once per machine and never again, even if you edit (macOS defaults — keeps daily `chezmoi apply` sudo-free).

---

## Troubleshooting

If `chezmoi apply` ever prompts you about a file in `$HOME` having changed, the safest answer is `d` (diff) → look at it → then `o` (overwrite) if the changes don't matter, or `m` (merge) if they do.

A few specific issues worth knowing about:

**`./install.sh: permission denied`** — run it as `bash install.sh` instead, or `chmod +x install.sh` first. To make the bit stick across clones: `git update-index --chmod=+x install.sh && git commit`.

**Sudo hangs at "Waiting for data..." during `chezmoi apply`** — already fixed in the macos-defaults wrapper (it reopens `/dev/tty` so sudo can prompt). If you still see this somehow, run `macos-defaults` manually instead — that always has a real TTY.

**Brew bundle fails: `Error: It seems there is already a Binary at '/opt/homebrew/bin/claude'`** — both `claude-code` and `claude-code@latest` casks install the same binary. The Brewfile pins to `claude-code@latest` (rolling channel). If you have plain `claude-code` installed, `brew uninstall --cask claude-code` and apply again.

**`chezmoi apply -v` hangs at `tightening permissions on /opt/homebrew/share/zsh*`** — should finish in <1s now (scoped to just the zsh dirs). If it hangs longer, you're probably running an old version of the script — Ctrl-C, `git pull` (or just re-run `chezmoi apply` from the source dir), and re-apply.

**Old `chezmoi apply` runs prompted about `.zsh_history`** — this used to fight with an active shell because `remove_dot_zsh_history` markers tried to delete a file the shell kept recreating. Those markers are gone. If you still have the legacy files (`~/.zsh_history` or `~/.config/zsh/.zsh_history`), delete them once: `rm -f ~/.zsh_history ~/.config/zsh/.zsh_history`.

---

## Reference

- [`MAPPING.md`](MAPPING.md) — every file in the repo and where it lands in `$HOME`, plus chezmoi internals.
- [`WORK-SETUP.md`](WORK-SETUP.md) — corporate Claude Code (`storecode`) install, separate from this repo.
- [`Brewfile`](Brewfile), [`Brewfile.personal`](Brewfile.personal), [`Brewfile.work`](Brewfile.work) — the three Brewfile tiers, with one-line rationale per package.
- [`examples/`](examples/) — drop-in starter files for `direnv` (`.envrc`) and `pre-commit` (`.pre-commit-config.yaml`) to use in your projects.
- [`.github/workflows/ci.yml`](.github/workflows/ci.yml) — shellcheck + chezmoi template-render check on every PR.

---

## License

MIT — see [`LICENSE`](LICENSE). Copy what's useful, discard what isn't. It's just my dotfiles.
