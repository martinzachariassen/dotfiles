# Obsidian canonical config

Renders to `~/.config/obsidian/`. The convergence script
`scripts/lib/obsidian-apply.sh` reads from here and seeds a vault's
`.obsidian/` directory with the canonical layout — theme, community plugins,
hotkeys, templates.

## Layout

- `plugins.txt` — `<plugin-id>|<github repo>` per line. Source of truth for
  which community plugins should be installed.
- `theme.txt` — `<theme-name>|<github repo>` (single line). Theme files are
  fetched directly from `main` since theme repos don't always publish releases.
- `vault-config/` — canonical `.obsidian/` overlay. Files here are seeded into
  the vault on first install and never overwritten afterwards (Obsidian's UI
  rewrites them on use; we don't fight that).
- `templates/` — canonical Templater templates. Seeded into the vault's
  `99 Meta/_templates/` on first install.
- `Home.md` — vault dashboard. Seeded into the vault root on first
  install; the Homepage plugin opens it on launch.
- `vault-guide.md` — user-facing how-to (PARA layout, hotkeys, where
  things go). Seeded into the vault as `99 Meta/Vault Guide.md` and
  linked from `Home.md`.

## How convergence works

`run_after_02d-obsidian-apply` runs on every `chezup`. It:

1. Locates the active vault via `~/Library/Application Support/obsidian/obsidian.json`.
2. Exits quietly if Obsidian isn't installed or no vault is registered yet
   (it's a no-op until you've opened Obsidian once and added a vault).
3. Ensures the theme + every plugin in `plugins.txt` is on disk (presence
   check, not freshness — freshness is `chezbump`'s job, same pattern as
   brew-bundle and mise-install).
4. Seeds missing config files and templates. Existing files are left alone so
   the in-app UI remains the source of truth for runtime changes.

To re-seed a file from canonical config, delete it from the vault and re-run
`chezup`. To pull plugin/theme updates, delete the relevant folder under
`.obsidian/plugins/` or `.obsidian/themes/` and re-run.
