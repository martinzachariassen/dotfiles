# `Library/` — macOS Application Support sources

Source for files that have to land under `~/Library/...` because that's where
the app reads them. chezmoi copies the source path literally, so the tree here
mirrors the destination one-to-one. Edit here, never the rendered file in
`$HOME`.

## What lives here, in one line

| Path                                                        | What it configures                                                   |
|-------------------------------------------------------------|----------------------------------------------------------------------|
| `Application Support/Code/User/settings.json.tmpl`          | VS Code user settings (rendered: JDK paths use `{{ .chezmoi.homeDir }}`). |
| `Application Support/Code/User/keybindings.json`            | VS Code editor-chrome chords (vim-mode maps live in `settings.json`). |

## What we want from you (agent) when editing here

- **One template, no extra files.** VS Code reads a single `settings.json` —
  keep everything in `settings.json.tmpl` with its existing section banners.
  Don't split into per-area files.
- **Catppuccin Frappé stays.** Same palette as Ghostty/Zellij/Starship/Neovim;
  don't drift the VS Code theme in isolation.
- **Extensions live elsewhere.** The marketplace ID list is
  `vscode/extensions.txt`, installed by
  `.chezmoiscripts/run_onchange_after_03-vscode.sh.tmpl`. If you add a setting
  for a new extension, add the extension ID there too.
- **Keybindings: macOS-default-safe.** New chords must not clobber a system
  binding. Mention in a comment what the chord does, like the existing entries.
- **JDK paths are mise-anchored.** `java.jdt.ls.java.home`,
  `java.configuration.runtimes[*].path`, and `intellij.jdkForSymbolResolution`
  point at `~/.local/share/mise/installs/java/temurin-<v>/Contents/Home`. The
  versions come from `dot_config/mise/config.toml`; keep them in sync.

## Verification

- `chezmoi execute-template < "Library/Application Support/Code/User/settings.json.tmpl"`
  to preview a render.
- `bash scripts/lint-config.sh` JSONC-validates `keybindings.json` (the
  template itself is skipped — the rendered file is only present after
  `chezmoi apply`).
- `bash scripts/render-check.sh` exercises the template via `chezmoi apply
  --dry-run` against stub data so a broken Go-template change fails CI.
