# Shell & command line

The command-line environment: plain zsh in an XDG layout, modern CLI
replacements wired into aliases, fuzzy-finding, mise-managed runtimes, and
git. No framework (oh-my-zsh/prezto/zinit) — the config in
[`src/dot_config/zsh/dot_zshrc.tmpl`](../src/dot_config/zsh/dot_zshrc.tmpl)
is extended directly.

## zsh

`ZDOTDIR=~/.config/zsh`, so the shell files live under `~/.config/zsh/`
(`.zshrc`, `.zprofile`); [`dot_zshenv`](../src/dot_zshenv) at `$HOME`
bootstraps that. The `.zshrc` is organised into labelled sections: shell
options, history, completion, key bindings, tool integrations, aliases, and
the dotfiles verbs.

Every integration is guarded — `command -v <tool> >/dev/null && …` — so a
fresh box starts cleanly *before* packages are installed, then lights up as
Homebrew fills in. That's the rule for any new integration here.

Tool integrations, in order: **fzf** (Ctrl-R history, Ctrl-T files,
`**<Tab>` completion), **zoxide** (frecency-based `cd`), **carapace** (richer
completions), **Starship** (prompt — see [terminal.md](terminal.md)), then
the brew zsh plugins (`zsh-autosuggestions`, `zsh-completions`, and
`zsh-syntax-highlighting` sourced **last**).

## Startup cost

Interactive startup is on the critical path of every new pane, so the `.zshrc`
is ordered and cached around it. Three things carry that:

- **The Zellij auto-attach runs first**, right after the `setopt` block. A
  Ghostty tab that attaches hands its terminal to Zellij, and the shell inside
  the pane sources the whole file again — so anything placed above the attach is
  parsed twice per tab. Only the helpers the attach itself needs live up there;
  the in-session hooks and `zj`/`zjclean` stay further down. The attach is a
  plain call, never `exec`, and nothing `return`s after it: detaching falls
  through to the rest of the file and leaves a fully configured shell.
- **`_zcache` memoises the `tool init` integrations.** `eval "$(mise activate
  zsh)"` and friends are a fork plus a parse on every shell (~44 ms for the five
  of them). `_zcache` writes the generated script to
  `$XDG_CACHE_HOME/zsh/init-<tool>.zsh`, byte-compiles it in the background, and
  sources the `.zwc` thereafter. It re-generates when the tool binary or the
  `.zshrc` is newer than the cache. Homebrew bottles occasionally restore an
  *older* mtime on upgrade, which defeats that check — `zshcache` clears
  everything by hand for those cases.
- **`compinit` rebuilds once a day, not never.** `compinit -C` skips the fpath
  re-scan and the security audit (~26 ms → ~15 ms), but used unconditionally it
  also means a newly brew-installed completion never shows up. The dump is
  rebuilt fully when it's older than 24 h and taken as-is otherwise, and it is
  keyed on `$ZSH_VERSION` so a zsh upgrade can't silently load an incompatible
  one.

`ZSH_PROFILE=1 zsh -i -c exit` prints a `zprof` table if you need to attribute a
regression. `tests/zshrc-wiring.bats` pins the structure above — the ordering,
the `_zcache` routing, and the non-`exec` attach — because none of it fails
loudly when it regresses; the shell just gets slower.

## Modern CLI replacements

Aliased only when present, and only where the replacement is a safe drop-in:

| Alias | Runs | Notes |
|---|---|---|
| `ls` / `ll` / `tree` | `eza` | `--group-directories-first`, git-aware; `tree` is eza's tree view. |
| `cat` | `bat --paging=never --style=plain` | Use `\cat` for bare output when piping to something ANSI-averse. |
| `find` | *(not aliased)* | `fd` isn't a drop-in — call `fd` directly; `find` keeps standard semantics. |

Plus single-letter shortcuts for the tools run constantly: `n` (nvim), `lg`
(lazygit), `g`/`gs`/`gd`/`gl` (git), `d`/`dc` (docker), `k`/`kgp`/`klf`
(kubectl, guarded), `tf` (terraform, when installed), `mw`/`gw`
(Maven/Gradle wrappers), `xcb`/`xcderived`/`simulator` (Xcode, `appleDev`
module only), and `mkcd` (mkdir + cd). `mkdir` and `find` are deliberately
*not* aliased — the notes in the `.zshrc` explain why.

## Runtimes (mise)

mise owns language runtimes — never asdf/nvm/jenv/pyenv/SDKMAN, and not
Homebrew. It also owns the handful of tools whose version a *project* wants to
pin (`just`), which is exactly the property a Brewfile can't give. Global
defaults live in
[`src/dot_config/mise/config.toml.tmpl`](../src/dot_config/mise/config.toml.tmpl)
and apply in any directory that doesn't pin its own; per-project versions
and env vars go in that project's committed `mise.toml` (its `[env]` block,
not direnv) and override the globals on `cd`.

The defaults:

| Tool | Version | Notes |
|---|---|---|
| Java | `temurin-25` | JVM stack (`jvmStack` module). |
| Node | `lts` | Resolves to the current LTS line at install time. |
| Python | `latest` | Tracks the newest stable release on each `mise install`. |
| Bun | `latest` | Tracks the newest stable release on each `mise install`. |
| Maven / Gradle | `latest` | `jvmStack` module. Project wrappers (`mvnw`/`gradlew`) still win. |
| just | `latest` | Command runner (Make-shaped). Here rather than in a Brewfile so a project's `mise.toml` can pin the version its `justfile` was written against. |

mise installs to stable paths
(`~/.local/share/mise/installs/<tool>/<version>`), so VS Code's Java server
anchors to a non-churning JDK path — see [editors.md](editors.md). Runtime
convergence runs on every apply via the `run_after_02b-mise-install` hook.

**Two ways in, on purpose.** Interactive shells get `mise activate` from
`.zshrc`, which swaps the real install dirs onto `PATH` on every `cd` — that's
what makes per-project versions and `JAVA_HOME` work. GUI apps never see it:
macOS starts them from launchd, and VS Code widens their `PATH` by resolving a
*non-interactive login* zsh (`.zshenv` + `.zprofile`, no `.zshrc`). So
[`.zprofile`](../src/dot_config/zsh/dot_zprofile) also prepends mise's shim dir
(`~/.local/share/mise/shims`), which needs no activate hook. Without it an
editor's language servers get a `PATH` with no JVM tooling on it at all and die
on spawn — VS Code's Kotlin LSP fails with `Cannot run program "mvn"`. Changing
a runtime version therefore needs no editor change, but **an editor already
running when this landed must be fully quit and relaunched** — the resolved env
is captured once, at app start.

## Containers (colima)

Docker Desktop is gone. `colima` runs dockerd inside a Lima VM and the plain
Homebrew `docker` CLI talks to it over the `colima` docker context — no GUI, no
licence terms, no `com.docker.vmnetd` privileged helper.

Four pieces, all in the core tier:

| Piece | Where |
|---|---|
| VM shape | [`src/dot_config/colima/_templates/default.yaml`](../src/dot_config/colima/_templates/default.yaml) |
| Start at login | [`src/Library/LaunchAgents/no.mlz.colima.plist.tmpl`](../src/Library/LaunchAgents/no.mlz.colima.plist.tmpl), registered by `run_onchange_after_07-colima` |
| CLI + plugins | `colima`, `docker`, `docker-compose`, `docker-buildx` in [`features/brew/Brewfile`](../features/brew/Brewfile) |
| Plugin wiring | `symlink_docker-{compose,buildx}` under [`src/dot_docker/cli-plugins`](../src/dot_docker/cli-plugins) |

The VM is 6 CPU / 8 GiB / 100 GiB sparse disk on `vz` (Apple's
Virtualization.framework) with `virtiofs` mounts and Rosetta on, so amd64 images
run without qemu's user-mode emulation. `$HOME` is mounted writable.

Two things are easy to get wrong:

- **The template only shapes a VM at creation.** Editing it does nothing to a VM
  that already exists — `colima delete && colima start` is what adopts a change.
- **colima resolves its home from `$XDG_CONFIG_HOME`, but only while `~/.colima`
  does not exist.** A bare `~/.colima` silently wins and strands the managed
  template. launchd doesn't read `.zshenv`, so the LaunchAgent exports
  `XDG_CONFIG_HOME` itself; the apply hook deletes an empty `~/.colima` and warns
  about a populated one.

Homebrew's plugin caveat suggests `cliPluginsExtraDirs` in `~/.docker/config.json`.
This repo uses chezmoi symlinks instead, because `docker login` writes credentials
into that same file and a `--force` apply would clobber them.

`colima start|stop|status` are aliased to `cstart`/`cstop`/`cstat`. `.zshrc` also
exports `TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock` — Testcontainers'
Ryuk bind-mounts the socket by its path *inside* the VM, and dies without it.

Logs: `~/.local/state/colima/logs/startup.log`.

## git

Config: [`src/dot_config/git/config.tmpl`](../src/dot_config/git/config.tmpl)
(XDG layout). Highlights:

- **Signing** — templated on your `signingMode` answer: `1password` (SSH
  signing via `op-ssh-sign`), `ssh-key` (plain SSH signing), or `off`. The
  signing block is emitted only when a mode is active *and* a `signingKey`
  is set, so key-less users never get a broken config. `bootstrap-auth.sh`
  finishes the 1Password wiring; see [install.md](install.md).
- **delta** as pager and diff filter (line numbers, navigate, custom status
  line matched to `$LESS`).
- **Sensible defaults** — `pull.rebase = true` + `ff = only`,
  `push.autoSetupRemote` + `followTags`, `rebase.autoStash/autoSquash`,
  `rerere` enabled, `fetch.prune`, `merge.conflictstyle = zdiff3`,
  `diff.algorithm = histogram`, fsmonitor + branch sort by commit date.
- **Aliases** — `s`, `co`, `sw`, `br`, `lg`, `last`, `unstage`, `amend`,
  `fixup`, `wip`, `undo` — and a `url` rewrite so pushes always go over SSH
  even when cloned via HTTPS.

For the interactive git TUI, `lg` → `lazygit` (core Brewfile).
