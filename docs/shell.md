# Shell & command line

The command-line environment: plain zsh in an XDG layout, modern CLI
replacements wired into aliases, fuzzy-finding, mise-managed runtimes, and git.
No framework (oh-my-zsh/prezto/zinit) — the config in
[`src/dot_config/zsh/dot_zshrc.tmpl`](../src/dot_config/zsh/dot_zshrc.tmpl) is
extended directly.

## zsh

`ZDOTDIR=~/.config/zsh`, so the shell files live under `~/.config/zsh/`
(`.zshrc`, `.zprofile`); [`dot_zshenv`](../src/dot_zshenv) at `$HOME` bootstraps
that. The `.zshrc` is organised into labelled sections: shell options, history,
completion, key bindings, tool integrations, aliases, and the dotfiles verbs.

Every integration is guarded — `command -v <tool> >/dev/null && …` — so a fresh
box starts cleanly *before* packages are installed, then lights up as Homebrew
fills in. That's the rule for any new integration here.

Tool integrations, in order: **fzf** (Ctrl-R history, Ctrl-T files, `**<Tab>`
completion), **zoxide** (frecency-based `cd`), **carapace** (richer completions),
**Starship** (prompt — see [terminal.md](terminal.md)), then the brew zsh plugins
(`zsh-autosuggestions`, `zsh-completions`, and `zsh-syntax-highlighting` sourced
**last**).

## Modern CLI replacements

Aliased only when present, and only where the replacement is a safe drop-in:

| Alias | Runs | Notes |
|---|---|---|
| `ls` / `ll` / `tree` | `eza` | `--group-directories-first`, git-aware; `tree` is eza's tree view. |
| `cat` | `bat --paging=never --style=plain` | Use `\cat` for bare output when piping to something ANSI-averse. |
| `find` | *(not aliased)* | `fd` isn't a drop-in — call `fd` directly; `find` keeps standard semantics. |

Plus single-letter shortcuts for the tools run constantly: `n` (nvim), `lg`
(lazygit), `g`/`gs`/`gd`/`gl` (git), `d`/`dc` (docker), `k`/`kgp`/`klf`
(kubectl, guarded), `tf` (terraform, work profile only), `mw`/`gw` (Maven/Gradle
wrappers), `xcb`/`xcderived`/`simulator` (Xcode, `appleDev` module only), and
`mkcd` (mkdir + cd). `mkdir` and `find` are deliberately *not*
aliased — the notes in the `.zshrc` explain why.

## Runtimes (mise)

mise owns language runtimes — never asdf/nvm/jenv/pyenv/SDKMAN, and not Homebrew.
Global defaults live in
[`src/dot_config/mise/config.toml.tmpl`](../src/dot_config/mise/config.toml.tmpl)
and apply in any directory that doesn't pin its own; per-project versions + env
vars go in that project's committed `mise.toml` (its `[env]` block, not direnv)
and override the globals on `cd`.

The defaults:

| Tool | Version | Notes |
|---|---|---|
| Java | `temurin-25` | JVM stack (`jvmStack` module). |
| Node | `lts` | Resolves to the current LTS line at install time. |
| Python | `latest` | Tracks the newest stable release on each `mise install`. |
| Bun | `latest` | Tracks the newest stable release on each `mise install`. |
| Maven / Gradle | `latest` | `jvmStack` module. Project wrappers (`mvnw`/`gradlew`) still win. |

mise installs to stable paths
(`~/.local/share/mise/installs/<tool>/<version>`), so VS Code's Java server
anchors to a non-churning JDK path — see [editors.md](editors.md). Runtime
convergence runs on every apply via the `run_after_02b-mise-install` hook.

## git

Config: [`src/dot_config/git/config.tmpl`](../src/dot_config/git/config.tmpl)
(XDG — global ignore at `~/.config/git/ignore`). Highlights:

- **Signing** — templated on your `signingMode` answer: `1password` (SSH signing
  via `op-ssh-sign`), `ssh-key` (plain SSH signing), or `off`. The signing block
  is emitted only when a mode is active *and* a `signingKey` is set, so key-less
  users never get a broken config. `bootstrap-auth.sh` finishes the 1Password
  wiring; see [install.md](install.md).
- **delta** as pager and diff filter (line numbers, navigate, custom status
  line matched to `$LESS`).
- **Sensible defaults** — `pull.rebase = true` + `ff = only`, `push.autoSetupRemote`
  + `followTags`, `rebase.autoStash/autoSquash`, `rerere` enabled, `fetch.prune`,
  `merge.conflictstyle = zdiff3`, `diff.algorithm = histogram`, fsmonitor + branch
  sort by commit date.
- **Aliases** — `s`, `co`, `sw`, `br`, `lg`, `last`, `unstage`, `amend`, `fixup`,
  `wip`, `undo` — and a `url` rewrite so pushes always go over SSH even when
  cloned via HTTPS.

For the interactive git TUI, `lg` → `lazygit` (core Brewfile).
