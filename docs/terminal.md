# Terminal

The terminal stack: **Ghostty** (emulator) running **zsh** inside **Zellij**
(multiplexer), with a **Starship** prompt, all in **Catppuccin Frappé**. The
zsh layer itself is in [shell.md](shell.md); this doc covers the surrounding
tools.

## Ghostty

Config: [`src/dot_config/ghostty/config.tmpl`](../src/dot_config/ghostty/config.tmpl).
JetBrainsMono Nerd Font at 13pt with ligatures (`calt`/`liga`), 12px padding,
subtle background blur/opacity, `bar` cursor, 100k scrollback.

Behaviour worth knowing:

- `copy-on-select = clipboard` — selecting text copies to the system
  clipboard, matching Zellij's `copy_on_select` so it's consistent inside and
  outside a session.
- `macos-option-as-alt = false` — keeps Option free for macOS Unicode/dead-key
  input such as `å`.
- `shell-integration = zsh` is injected automatically; nothing extra in
  `.zshrc`.
- Keybinds: `Cmd+K` clear, `Cmd+Enter` fullscreen, `Cmd+Shift+.` inspector;
  tab bindings are Ghostty defaults.

> [!NOTE]
> Ghostty does **not** support inline comments — every comment must be on its
> own line, or the value parses wrong and the app throws a config error on
> launch.

The theme is a **local** file
(`src/dot_config/ghostty/themes/catppuccin-frappe`) rather than a built-in
name, for deterministic colors across Ghostty versions. Applied only when the
`theme` module is selected.

## Zellij

Config: [`src/dot_config/zellij/config.kdl`](../src/dot_config/zellij/config.kdl).
A modern tmux alternative: `default_shell zsh`, custom `main` layout with a
one-line [zjstatus](https://github.com/dj95/zjstatus) bar
([`layouts/main.kdl`](../src/dot_config/zellij/layouts/main.kdl)),
`copy_on_select` → `pbcopy`, mouse mode on, sessions serialized across
restarts, rounded pane frames showing pane titles.

Interactive Ghostty shells auto-attach to Zellij; each window gets its own
session — the project (cwd) name for the first, `-2`/`-3`… suffixes for
later windows in the same directory. A new window always lands in a *fresh*
session: exited sessions are pruned on startup and never silently
resurrected, so a new tab is always clean and two windows never co-attach
(which would mirror keystrokes). `zj [name]` attaches manually (an explicit
name joins or resurrects a session on purpose), `zjclean` prunes exited ones,
and `NO_ZELLIJ=1 zsh` is the escape hatch for a bare shell. Ghostty's own
`window-save-state = default` (not `always`) keeps a relaunch from restoring
every tab and multiplying detached sessions — Zellij owns persistence.

**New tabs open where you were.** A fresh Ghostty tab normally starts at `$HOME`
because Zellij never forwards the active pane's directory to Ghostty
([zellij#3811](https://github.com/zellij-org/zellij/issues/3811)), so
`window-inherit-working-directory` has nothing to inherit. The `.zshrc` bridges it:
each pane records its cwd to `$XDG_STATE_HOME/zellij/last-cwd` on every prompt/`cd`
(`_zj_record_cwd`), and a tab launched at `$HOME` reads it back and `cd`s there
before attaching (`_zj_inherit_cwd`), so the new session opens in — and is named
after — the project you were just in. Scope is "most-recently-active pane," so
across windows the last one you touched wins.

Keybinds are Zellij's mode-based defaults — `Ctrl+P` pane mode, `Ctrl+T` tab
mode, and `Ctrl+G` to lock/unlock Zellij's own bindings when an inner app
(vim) wants the same chord. Dump the full set with
`zellij setup --dump-config`.

## Starship

Config: [`src/dot_config/starship.toml`](../src/dot_config/starship.toml),
palette `catppuccin_frappe`. A two-line prompt: context on line 1, prompt
character on line 2. Modules cover development and cloud tooling and
self-disable when irrelevant — directory, git branch/status, language
versions (Java/Kotlin/Node/Python), Terraform, Docker context, Kubernetes,
Azure, gcloud, and command duration.

## Theme

Catppuccin Frappé is applied across Ghostty, Zellij, Starship, and the
editor when the `theme` module is selected — see
[packages.md](packages.md#optional-modules). JetBrainsMono Nerd Font (core
Brewfile) is the shared font across terminal and VS Code.
