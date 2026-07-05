# Terminal

The terminal stack: **Ghostty** (emulator) running **zsh** inside **Zellij**
(multiplexer), with a **Starship** prompt, all in **Catppuccin Frappé**. The zsh
layer itself is in [shell.md](shell.md); this doc covers the surrounding tools.

## Ghostty

Config: [`src/dot_config/ghostty/config.tmpl`](../src/dot_config/ghostty/config.tmpl).
JetBrainsMono Nerd Font at 13pt with ligatures (`calt`/`liga`), 12px padding,
subtle background blur/opacity, `bar` cursor, 100k scrollback.

Behaviour worth knowing:

- `copy-on-select = clipboard` — selecting text copies straight to the system
  clipboard, matching Zellij's `copy_on_select` so it's consistent inside and
  outside a session.
- `macos-option-as-alt = false` — keeps Option free for macOS Unicode/dead-key
  input such as `å`.
- `shell-integration = zsh` is injected automatically; nothing extra needed in
  `.zshrc`.
- Keybinds: `Cmd+K` clear, `Cmd+Enter` fullscreen, `Cmd+Shift+.` inspector; tab
  bindings are Ghostty defaults.

> Ghostty does **not** support inline comments — every comment must be on its own
> line, or the value parses wrong and the app throws a config error on launch.

The theme is a **local** file
(`src/dot_config/ghostty/themes/catppuccin-frappe`) rather than a built-in name,
for deterministic colors across Ghostty versions. It's applied only when the
`theme` module is selected.

## Zellij

Config: [`src/dot_config/zellij/config.kdl`](../src/dot_config/zellij/config.kdl).
The multiplexer (a modern tmux alternative), `default_shell zsh`,
`compact` layout for a minimal status bar. `copy_on_select` → `pbcopy`, mouse
mode on, sessions serialized across restarts, pane frames off (rounded when on).
Each Ghostty tab is an independent Zellij session (`mirror_session false`).

Keybinds are Zellij's mode-based defaults — `Ctrl+P` pane mode, `Ctrl+T` tab
mode, and `Ctrl+G` to lock/unlock Zellij's own bindings when an inner app (vim)
wants the same chord. Dump the full set with `zellij setup --dump-config`.

## Starship

Config: [`src/dot_config/starship.toml`](../src/dot_config/starship.toml), palette
`catppuccin_frappe`. A two-line prompt: context on line 1, prompt character on
line 2. Modules are scoped to backend + cloud work and self-disable when
irrelevant — directory, git branch/status, language versions
(Java/Kotlin/Node/Python), Terraform, Docker context, Kubernetes, Azure, gcloud,
and command duration.

## Theme

Catppuccin Frappé is applied across Ghostty, Zellij, Starship, and the editor
when the `theme` module is selected — see [packages.md](packages.md#optional-modules).
JetBrainsMono Nerd Font (core Brewfile) is the shared font across terminal and
VS Code.
