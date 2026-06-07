# `dot_config/` — XDG config sources

Source for everything that renders into `~/.config/`. chezmoi prefix rules:
`dot_*` → `.X`, `private_dot_*` → mode-0600, `.tmpl` is a Go template.
Edit here, never the rendered file in `$HOME`.

## What lives here, in one line

| Folder / file        | What it configures                                                |
|----------------------|-------------------------------------------------------------------|
| `claude/`            | Claude Code memory — profile picker + shared base, all templated. |
| `ghostty/`           | Terminal emulator + custom Catppuccin Frappé theme file.          |
| `git/`               | Global git config, allowed signers, XDG global ignore.            |
| `mise/`              | Global runtime defaults (JDK, Node, Python, Maven, Gradle).       |
| `nvim/`              | LazyVim bootstrap, plugin lockfile, Catppuccin override.          |
| `obsidian/`          | Canonical vault overlay — plugins, templates, dashboard, guide.   |
| `starship.toml`      | Shell prompt — modules, palette, cloud/cluster context.           |
| `zellij/`            | Terminal multiplexer config.                                      |
| `zsh/`               | `.zprofile` (login PATH) + `.zshrc` (interactive shell).          |

## What we want from you (agent) when editing here

- **Preserve the look.** Catppuccin Frappé is the one palette across Ghostty,
  Zellij, Starship, Neovim, Obsidian, VS Code. Don't drift.
- **Respect the engine boundary.** Language runtimes belong in `mise/`;
  global CLIs belong in the Brewfiles at the repo root. Don't move tools
  between them without a reason.
- **Templates are explicit.** A `.tmpl` file means it's rendered by chezmoi
  with `.profile`, `.email`, `.signingKey`, etc. Keep template logic small;
  body content belongs in `.chezmoitemplates/` when it'd otherwise be inlined
  twice (see `claude/CLAUDE.shared.md.tmpl`).
- **Keep the existing comment style.** Files explain *why*, point at the edit
  command (`chezmoi edit ~/.config/X`), and call out non-obvious choices
  (e.g. `compinit -C`, `mnemonicPrefix`, ligature-aware fonts). Match that
  voice if you add a section.
- **Don't touch managed runtime state silently.** `nvim/lazy-lock.json` and
  the `obsidian/vault-config/plugins/*/data.json` files are deliberately
  tracked snapshots — bumps go through `:Lazy update` + `chezmoi add` or
  through the Obsidian UI + reseed flow, not hand-edits.
- **Profile gating.** Anything that diverges between `personal` and `work`
  goes behind `{{ if eq .profile "work" }}` in the relevant `.tmpl`, not in
  a separate file.

## Gotchas worth remembering

- **Ghostty has no inline comments.** Every `#` must start a line.
- **`/etc/zshrc` runs between `.zshenv` and `.zshrc`** and resets `HISTFILE`
  — `.zshrc` re-exports it on purpose.
- **Obsidian seeding is one-way.** `vault-config/` and `templates/` are
  copied into a vault only when absent; the UI owns runtime state after that.
- **Plugin pins** in `obsidian/plugins.txt` use the optional `|<tag>` third
  column — only pin when the latest release is unusable, and document why on
  the line above.
- **Signing is conditional.** `git/config.tmpl` only emits commit-signing
  blocks when both `useOnePassword` and `signingKey` are set.

## Verification

Most files render and reload on `chezup`. For targeted checks:

- `chezmoi execute-template < dot_config/<path>.tmpl` to preview a render.
- `zsh -n ~/.config/zsh/.zshrc` for shell syntax.
- `starship explain` / `starship config` to sanity-check the prompt.
- `nvim --headless "+Lazy! sync" +qa` to validate the plugin spec.
