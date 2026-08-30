# Untracked dotfiles

`chez clean` (today: `chezclean`) is the confirm-gated **file** analogue of
`chezmirror`. An apply never deletes — it only renders what the repo tracks — so
untracked cruft accumulates: a directory some tool dropped, config for a package
you removed months ago. This is the step that reconciles it, and it only ever
runs because you ran it.

## Verbs

- `chez clean` — Remove untracked top-level `~/.*` entries, confirming each.

## How it works

Two scopes, both reading their keep-list from
[`src/.chezmoidata/clean.toml`](../../src/.chezmoidata/clean.toml):

- **The top level of `$HOME`** — untracked `~/.*` entries, spared by
  `cleanup.keepHome`. This scope cannot be `exact_`: `$HOME` also holds
  `~/Library`, `~/Documents` and everything else you own.
- **`~/.config`** — untracked `~/.config/X`, spared by `cleanup.keepConfig`:
  auth and state directories like `op`, `gh`, `gcloud`, and chezmoi's own
  `~/.config/chezmoi`.

Neither scope descends past its immediate children, so a managed subdirectory
(`nvim`, `zsh`, …) keeps its own untracked contents — caches, `.zcompdump`,
local overrides.

### Tool-awareness

Config whose owning tool is still installed is kept automatically and never
offered. "Still installed" is the union of three signals:

1. its Homebrew package is installed,
2. its command is on `PATH` — so tools from mise, gcloud and npm count,
3. or its owning VS Code extension is in `code --list-extensions`.

Uninstall the tool, or drop the extension, and its leftovers re-surface as
removable. Most entries match by a stem heuristic (`command -v <name-minus-dot>`,
so `.gradle` → `gradle`). The `cleanup.owners` map supplies only the aliases
where the directory name and the tool's command, package or extension diverge:
`.kube` → `kubectl`, `.m2` → `mvn` (from mise), `.lemminx` → the
`redhat.vscode-xml` extension.

Offered entries are labelled `orphan` (a known tool, now gone) or `untracked`
(no known owner). `-v`/`--verbose` also lists what tool-ownership kept.

### Safe by construction

- Only names beginning with `.` are ever considered, so `~/Library`,
  `~/Documents` and the rest are structurally out of scope.
- It never descends past an immediate child.
- It removes nothing without a controlling terminal.
- Nothing goes without a confirmation, unless you pass `--all` (`-a`/`--yes`/`-y`)
  to accept the whole set after one, or `YES=1` to accept all with no prompt.
  Both still require a TTY. `DRY_RUN=1` (or `-n`/`--dry-run`) previews and works
  headless.

## Keeping something for good

Add it to `cleanup.keepHome` or `cleanup.keepConfig`. If it is a tool whose
directory name diverges from its command, add an `owners` alias instead — then it
is kept while the tool is installed and offered once it is not, which is usually
what you actually want.

## Gotchas

- **`clean.toml` is the single source of truth for all three lists**
  (`keepConfig`, `keepHome`, `owners`), so the two scopes cannot drift apart.
  The file was named `cleanup.toml` until this feature moved; its top-level TOML
  table is still `[cleanup]`, because that key — not the filename — is what
  `chezmoi data` exposes.
- **`~/.storecode` is permanently on `keepHome`.** storecode is installed by its
  own hook rather than by a Brewfile, so nothing else would keep it alive. See
  [features/storecode](../storecode/README.md).
- Package removal is a different verb. `chezmirror` handles Homebrew;
  `chezreconcile` chains install-then-remove for packages. Files stay here.
