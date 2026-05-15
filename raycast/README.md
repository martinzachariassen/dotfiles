# Raycast Backups

Raycast does not expose a stable plain-text dotfile for its full app state.
Its supported backup format is an encrypted `.rayconfig` export.

Use this folder as the scheduled export target:

1. Open Raycast Settings -> Advanced -> Export.
2. Set an export passphrase and store it in 1Password.
3. Set the scheduled backup location to:

   ```text
   ~/Developer/personal/dotfiles/raycast
   ```

The export can include settings, aliases, hotkeys, extensions, snippets,
quicklinks, notes, clipboard history, AI data, MCP servers, and window layouts.
The file is encrypted, but treat it as sensitive backup material.

On a new Mac, install Raycast through the `macApps` feature, then run Raycast's
`Import Settings & Data` command and choose the latest `.rayconfig` file from
this folder.
