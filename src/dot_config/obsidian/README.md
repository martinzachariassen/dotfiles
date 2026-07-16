# Obsidian canonical config

Renders to `~/.config/obsidian/`. The convergence script
`scripts/lib/obsidian-apply.sh` reads from here and seeds a vault's
`.obsidian/` directory with the canonical layout — theme, community plugins,
hotkeys, templates.

## Layout

- `plugins.txt` — `<plugin-id>|<github owner/repo>[|<release-tag>]` per line
  (the optional third field pins a release when `/releases/latest` is
  unusable — see the Templater line). Source of truth for which community
  plugins should be installed.
- `theme.txt` — `<theme-name>|<github repo>[|<branch>]` (single line). Theme
  files are fetched from the given branch (default `main`) since theme repos
  don't always publish releases or use the same default branch name.
- `vault-config/` — canonical `.obsidian/` overlay. Files here are seeded into
  the vault on first install and never overwritten afterwards (Obsidian's UI
  rewrites them on use; we don't fight that).
- `templates/` — canonical Templater templates. Seeded into the vault's
  `99 Meta/_templates/` on first install.
- `scripts/` — canonical QuickAdd/Templater user scripts (e.g. `file-note.js`,
  the "File this…" mover). Seeded into the vault's `99 Meta/_scripts/` on first
  install; referenced by path from plugin config (`plugins/quickadd/data.json`).
- `bases/` — canonical `.base` files (core Bases database views, e.g.
  `Projects.base`). Seeded into the vault root on first install; linked from
  `Home.md` for at-a-glance project/area oversight.
- `folder-readmes/` — per-folder `_README.md` files. Each source is named
  after its target folder verbatim (`10 Areas.md` → `10 Areas/_README.md`),
  so seeding needs no lookup table and `mkdir -p` lays down the top-level
  folder structure on a fresh vault.
- `Home.md` — vault dashboard. Seeded into the vault root on first
  install; the Homepage plugin opens it on launch.
- `vault-guide.md` — user-facing how-to (PARA layout, hotkeys, where
  things go). Seeded into the vault as `99 Meta/Vault Guide.md` and
  linked from `Home.md`.

`vault-config/` also carries `types.json` (property type registry, so dates,
numbers, and lists render with the right widget) and
`plugins/obsidian-icon-folder/data.json` (per-folder Lucide icons + Catppuccin
colors). Per-note icons are driven by `icon`/`iconColor` frontmatter that the
templates set, not by the Iconize config.

## How convergence works

`run_after_02d-obsidian-apply` runs on every `chezup`. It:

1. Locates the active vault via `~/Library/Application Support/obsidian/obsidian.json`.
2. Exits quietly if Obsidian isn't installed or no vault is registered yet
   (it's a no-op until you've opened Obsidian once and added a vault).
3. Ensures the theme + every plugin in `plugins.txt` is on disk (presence
   check, not freshness — freshness is `chezbump`'s job, same pattern as
   brew-bundle and mise-install).
4. Seeds missing config files, templates, user scripts, bases, folder READMEs,
   `Home.md`, and the Vault Guide. Existing files are left alone so the in-app
   UI remains the source of truth for runtime changes.

To re-seed a file from canonical config, delete it from the vault and re-run
`chezup`. To pull plugin/theme updates, delete the relevant folder under
`.obsidian/plugins/` or `.obsidian/themes/` and re-run.

## Vault backup (obsidian-git, currently not enabled)

This repo manages the vault's *config*, not its *content* — your notes are
yours and live only in the iCloud vault. iCloud is sync, not backup: a bad
delete or a corrupt note propagates everywhere with no undo. `obsidian-git`
versions the content to a **private** remote, but it's deliberately left out
of `plugins.txt`/`community-plugins.json` for now — it's one more moving part
for a problem you haven't hit yet. To bring it back: add
`obsidian-git|Vinzent03/obsidian-git` to `plugins.txt` and `"obsidian-git"` to
`vault-config/community-plugins.json`, then re-create
`vault-config/plugins/obsidian-git/data.json` (Obsidian Git writes its own
settings there once configured in-app — seed an empty `{}` and let the plugin
fill it in). One-time repo setup, run once per vault (not per machine —
iCloud carries the `.git` dir to your other devices):

```sh
# 1. Create an EMPTY private repo first (gh or the web UI):
gh repo create my-obsidian-vault --private

# 2. In the vault root (mind the spaces in the iCloud path):
cd "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/The Archive"
git init
cat > .gitignore <<'EOF'
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.trash/
.DS_Store
EOF
git add -A
git commit -m "vault backup: initial"
git branch -M main
git remote add origin git@github.com:<you>/my-obsidian-vault.git
git push -u origin main
```

Then in Obsidian: **Settings → Community plugins → enable Obsidian Git**. It
auto-commits and pushes every 30 min and pulls on launch (see the seeded
`data.json`). Restore any note from `git log` / GitHub history.

**iCloud + `.git` caveat:** the `.git` dir syncs through iCloud too, so
concurrent edits on two devices can conflict. The seeded *pull-on-boot* setting
mitigates it; the safe habit is to let a device finish syncing (and Obsidian
Git commit) before editing on another.
