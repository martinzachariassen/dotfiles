# dotfiles

My personal macOS setup, managed by [chezmoi](https://chezmoi.io). One command bootstraps a fresh Mac into a fully configured dev environment.

The repo lives at `~/Dev/Personal/dotfiles`.

---

## Bootstrap

On a fresh Mac, open Terminal and run:

```sh
curl -fsSL https://raw.githubusercontent.com/martinzachariassen/dotfiles/main/install.sh | bash
```

The script is a guided 8-step tour with explanations at each step. It's idempotent — re-running is safe. Total time: ~15–20 minutes (mostly Homebrew downloading).

The 8 steps:

1. **Xcode Command Line Tools** — a GUI dialog appears. Click *Install*, wait, re-run the script (it exits with a hint).
2. **Homebrew** — installed non-interactively at the Apple Silicon path.
3. **chezmoi** — installed via `brew install chezmoi`.
4. **Clone repo** to `~/Dev/Personal/dotfiles`.
5. **Configure chezmoi** — prompts for **profile** (personal / work / both) and **identity** (name, git email, SSH signing key). Answers stored in `~/.config/chezmoi/chezmoi.toml` and persist across re-runs.
6. **Apply dotfiles + install packages** — writes every dotfile, then runs `brew bundle` against the appropriate Brewfiles for your profile, installs VS Code extensions, applies macOS defaults (sudo prompt).
7. **Re-render config** — re-runs `chezmoi init` so the `[diff] pager = "delta"` block picks up the now-installed `delta`.
8. **Self-test** — verifies key tools and apps actually landed.

When it's done, sign in to 1Password (so the SSH agent works), `gh auth login`, optionally `gcloud auth login`, then `exec zsh` to reload, and restart so all the macOS defaults take effect.

### Profiles

The `profile` answer at step 5 controls which packages and shell config get installed:

| Profile | What you get |
|---|---|
| `personal` | Common Brewfile + `Brewfile.personal` (Claude desktop + Claude Code CLI cask, plus any other personal-only apps you add). Personal-only `.zshrc` block renders. |
| `work` | Common Brewfile + `Brewfile.work` (work-only apps you add — Slack, Teams, Postman, etc.). Work-only `.zshrc` block renders, including `~/.storecode/bin` on PATH if installed. Personal Claude casks are *not* installed (work uses storecode-managed `~/.claude` per [`WORK-SETUP.md`](WORK-SETUP.md)). |
| `both` | Common Brewfile + both extras + both `.zshrc` blocks. Useful for a single-machine-many-jobs setup. |

To switch profiles later, edit `~/.config/chezmoi/chezmoi.toml` and change the `profile = "..."` value, then `chezmoi apply -v`. The brew-bundle script will install whichever extras the new profile requires (it doesn't auto-uninstall the old profile's packages — `brew uninstall <name>` manually if you want to clean up).

---

## What you get

| Area | What's in the box |
|---|---|
| **Terminal** | [Ghostty](https://ghostty.org) with Catppuccin Frappé, JetBrainsMono Nerd Font, transparent titlebar, blurred background. Theme is built into Ghostty so the config is short. |
| **Multiplexer** | [Zellij](https://zellij.dev) with the built-in Catppuccin Frappé theme, compact layout, mouse + clipboard integration, session persistence. Launch with the `zj` alias. Auto-attach on shell startup is opt-in (commented snippet in `.zshrc`). |
| **Prompt** | [Starship](https://starship.rs) with Catppuccin Frappé palette. Two-line prompt that surfaces git branch/status, language versions (Java/Node/Python/Go), Kubernetes context, and AWS profile only when relevant — keeps it clean otherwise. See [the prompt examples](#what-the-prompt-looks-like) below. |
| **Shell** | zsh with XDG layout, mise activation, fzf integration, `zsh-completions`, `zsh-syntax-highlighting`, claude work/personal wrapper, modern CLI aliases (`ls→eza`, `cat→bat`, `find→fd`) |
| **Git** | Identity + 1Password commit signing, delta diffs, useful aliases, pull rebase, rerere |
| **Runtimes** | mise: Java 21 (Temurin), Maven, Gradle, Node, pnpm, Python — all "latest", overridable per-project |
| **Brew** | ~50 packages — full list and rationale per package in [`Brewfile`](Brewfile). Categories: modern CLI replacements, git productivity (`lazygit`, `pre-commit`, `direnv`), Kubernetes (`kubectx`, `stern`, `k9s`), cloud + IaC (`awscli`, `gcloud-cli`, `opentofu`), DB clients (`pgcli`, `mysql-client`, `redis-cli`), container introspection (`dive`), backend HTTP/RPC (`grpcurl`, `mkcert`), plus the GUI app casks. |
| **Editor (GUI)** | VS Code with Catppuccin Frappé, Material Icon Theme, Python + Pylance + black-formatter + Containers extensions, format on save |
| **Editor (terminal)** | [Neovim](https://neovim.io) with [LazyVim](https://www.lazyvim.org) and the Catppuccin Frappé flavor of `catppuccin/nvim`. First launch auto-installs `lazy.nvim`, then LazyVim pulls in LSP (via mason), treesitter, telescope, nvim-tree, which-key, gitsigns, and the rest of the standard distribution. Backend-dev language extras (Java, Python, TypeScript, JSON, YAML, Docker, Terraform, Markdown) ship commented-out in `lua/config/lazy.lua` — uncomment whichever you want and re-launch. |
| **macOS** | Fast key repeat, no autocorrect, full keyboard nav, Finder shows everything, Dock auto-hide, screenshots → `~/Pictures/Screenshots` |

Full source-to-destination mapping in [`MAPPING.md`](MAPPING.md).

### What the prompt looks like

Starship modules show up only when they're contextually relevant, so the prompt grows with the situation. A few examples (rendered without color here, but in Ghostty they're Catppuccin-tinted):

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

```sh
chezmoi edit ~/.zshrc           # edit a managed file
chezmoi diff                    # preview pending changes
chezmoi apply -v                # apply changes (silent on subsequent runs — no sudo, no prompts)
chezmoi update                  # git pull + apply
```

To add a new tool: install with `brew install <name>`, append the line to `Brewfile`, then `chezmoi add ~/.config/<name>/config.toml` to manage its config.

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

# Terminal & multiplexer
zj                           # zellij attach -c default — named session, detach/reattach friendly

# Claude Code profile (also auto-routes by PWD)
cw                           # work profile  (CLAUDE_CONFIG_DIR=~/.claude)
cme                          # personal profile (CLAUDE_CONFIG_DIR=~/.config/claude/personal)

# Maintenance ceremonies (run on demand, NOT on every chezmoi apply)
macos-defaults               # re-apply system settings (sudo prompt; idempotent)
```

---

## Claude Code: work vs personal

A wrapper function in `.zshrc` routes `claude` based on PWD:

- Anywhere under `~/Dev/Work/` → uses `~/.claude` (work profile, managed by employer's tooling — see [`WORK-SETUP.md`](WORK-SETUP.md))
- Everywhere else → uses `~/.config/claude/personal`

Override with `cw` (work) or `cme` (personal) aliases.

The CLI binary comes from the `cask "claude-code@latest"` line in the Brewfile.

---

## Troubleshooting

If `chezmoi apply` ever prompts you about a file in `$HOME` having changed, the safest answer is `d` (diff) → look at it → then `o` (overwrite) if the changes don't matter, or `m` (merge) if they do. The setup intentionally only manages files where chezmoi should be the source of truth, so prompts on managed files are rare.

A few specific issues worth knowing about:

**`./install.sh: permission denied`** — run it as `bash install.sh` instead, or `chmod +x install.sh` first.

**Sudo hangs at "Waiting for data..." during `chezmoi apply`** — already fixed in the macos-defaults wrapper (it reopens `/dev/tty` so sudo can prompt). If you still see this somehow, run `macos-defaults` manually instead.

**Brew bundle fails on `claude-code` saying `/opt/homebrew/bin/claude` already exists** — you have both `claude-code` and `claude-code@latest` partially installed. Pick one: `brew uninstall --cask claude-code` (keeps `@latest`, matches the Brewfile) or edit the Brewfile if you'd rather pin to the stable channel.

---

## Reference

- [`MAPPING.md`](MAPPING.md) — every file in the repo and where it lands in `$HOME`, plus chezmoi internals
- [`WORK-SETUP.md`](WORK-SETUP.md) — corporate Claude Code install, separate from this repo
- [`examples/`](examples/) — drop-in starter files for `direnv` (`.envrc`) and `pre-commit` (`.pre-commit-config.yaml`) to use in your projects
- [`Brewfile`](Brewfile) — full list of installed packages with one-line rationale per entry

MIT licensed — see [`LICENSE`](LICENSE).
