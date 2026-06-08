---
type: guide
icon: LiCompass
iconColor: "#ca9ee6"
tags: [meta, guide]
---
# Vault Guide

Everything you need to work in this vault: where things go, how to create
them, and which keys to press. Linked from [[Home]] — press `⌘O` and type
"Vault Guide" to jump back any time.

> [!tip] The 10-second version
> **Capture** with `⌘⇧N` → everything lands in `00 Inbox`. **File** it at your
> weekly review into Projects / Areas / Resources. Create a typed note simply
> by **making a new note inside the matching folder** — the right template
> applies itself.

## The PARA layout

Folders are sorted by **actionability**, not topic. Pick a folder by asking
*"how soon will I act on this?"*

| Folder | What goes there | The question |
|---|---|---|
| `00 Inbox` | Unsorted captures, ideas, links | "I'll deal with it later" |
| `10 Daily` | Daily / weekly / monthly notes | (auto — see Periodic notes) |
| `20 Projects` | Work with an outcome + end date | "I want to finish X by Y" |
| `30 Areas` | Ongoing responsibilities, no deadline | "I maintain X indefinitely" |
| `40 Resources` | Reference, snippets, reading, people | "I might want this again" |
| `50 Archive` | Finished projects, retired areas | "Done. Keep for search." |
| `99 Meta` | Templates, attachments, this guide | (vault plumbing) |

Each folder has a `_README.md` explaining its scope. The leading underscore
pins it to the top of the file list.

## Keyboard shortcuts

| Key | What happens |
|---|---|
| `⌘⇧N` | **Capture to inbox** (QuickAdd) — prompts for a title, drops a timestamped note in `00 Inbox/` |
| `⌘⇧T` | Open **today's daily** note (created from `daily.md` if missing) |
| `⌘⇧W` | Open **this week's** weekly note |
| `⌘⇧I` | **Insert a template** into the current note (Templater picker) |
| `⌘O` | **Quick switcher** — find any note by name |
| `⌘P` | **Command palette** — every command lives here |
| `⌘⌥F` | Search within the file explorer |
| `⌘⌥←` / `⌘⌥→` | Toggle the left / right sidebar |

Monthly notes have no default key — open one via `⌘P → "Open monthly note"`
or click a month in the Calendar sidebar.

## Creating notes

There are three ways a note gets the right template and properties:

1. **Folder auto-templates.** Make a new note *inside* one of these folders
   and its template runs automatically (prompting for a name where needed):

   | Folder | Auto-applies |
   |---|---|
   | `00 Inbox` | `inbox` |
   | `20 Projects` | `project` |
   | `30 Areas` | `area` |
   | `40 Resources/42 People` | `person` |
   | `40 Resources/43 Reading` | `reading` |

2. **Periodic Notes.** `⌘⇧T` / `⌘⇧W` (and monthly via the palette) create
   dated notes in `10 Daily/YYYY/` from their templates.

3. **Insert manually.** Press `⌘⇧I` anywhere to pick any template — handy for
   `meeting` and `note`, which aren't tied to a folder.

## Templates

All templates live in `99 Meta/_templates/` and use **Templater** syntax
(`<%* … %>`). Each one sets a `type`, an `icon`, a `created` stamp, and
type-specific properties.

| Template | How you get it | Sets up |
|---|---|---|
| `inbox` | `⌘⇧N`, or new note in `00 Inbox` | Timestamped capture |
| `daily` | `⌘⇧T` | Day note: prev/next nav, today's tasks, log |
| `weekly` | `⌘⇧W` | Week note: Mon–Sun range, daily roll-up |
| `monthly` | `⌘P → Open monthly note` | Month note: rolls up the weeklies |
| `project` | New note in `20 Projects` | Goal, next actions, decisions, log |
| `area` | New note in `30 Areas` | Standards, focus, related projects |
| `meeting` | `⌘⇧I` | Agenda, notes, decisions, action items |
| `person` | New note in `42 People` | Role, 1:1 history, topics |
| `reading` | New note in `43 Reading` | Author, source, status, rating, highlights |
| `note` | `⌘⇧I` | Lightweight generic note |

To add a template, drop a `.md` file with `<%* … %>` at the top into
`99 Meta/_templates/`. It appears in the picker immediately.

## Frontmatter (properties)

Every note carries a `type` so dashboards can filter reliably. Properties are
**registered with types** (in `.obsidian/types.json`), so dates show a
date-picker, `rating` is a number, lists are chips, etc.

```yaml
---
type: project          # inbox | daily | weekly | monthly | project | area | meeting | person | reading | note
icon: LiFolderKanban   # Lucide icon shown by the title (Iconize)
iconColor: "#a6d189"   # hex, must be quoted (# starts a YAML comment otherwise)
created: 2026-06-08 14:30
status: active          # active | paused | done  (free text, autocompletes)
domain: work           # work | personal
priority: high         # high | medium | low
started: 2026-06-08    # dates render as a picker
target:                # deadline
related: []            # links to related notes
tags: [project]
---
```

Common fields by type: **project** → `status, domain, priority, started,
target, area`; **reading** → `category, author, url, status, rating,
started, finished`; **person** → `role, team, company, email, first-met`;
**area** → `domain, status, review`.

## Icons & colors

- **Folders** are colored by PARA tier (Iconize): Inbox red, Daily blue,
  Projects green, Areas teal, Resources mauve, Archive/Meta gray.
- **Notes** show a per-type icon by the title, driven by the `icon` /
  `iconColor` frontmatter that templates add for you.
- To change one by hand: right-click a folder/note → **Change icon** /
  **Change color**, or edit the `icon` property. Lucide IDs are `Li` +
  PascalCase (e.g. `LiBookOpen`).

## Where do I put this?

1. **Half-baked / unsorted?** → `00 Inbox`. Sort it at the weekly review.
2. **Outcome + finish line?** → `20 Projects` (own subfolder).
3. **Tend it indefinitely?** → `30 Areas` → `31 Work` / `32 Personal` / `33 Learning`.
4. **Reference I'll want again?** → `40 Resources` → `41 Tech` / `42 People` / `43 Reading`.
5. **A person?** → `42 People`.  **Something to read?** → `43 Reading`.
6. **A meeting?** → next to its project, or in `42 People` for 1:1s (`meeting` template).
7. **Done / inactive?** → `50 Archive`. Move, don't delete.

## Weekly review

Once a week: open this week's note (`⌘⇧W`), empty `00 Inbox` (file or
archive each item), glance at **Active projects** on [[Home]], and set next
week's focus. Monthly, do the same one level up with the monthly note.

## Plugins in play

| Plugin | What it does |
|---|---|
| Templater | Dynamic templates (`<%* … %>`) |
| QuickAdd | `⌘⇧N` capture flow |
| Periodic Notes | Daily / weekly / monthly note lifecycle |
| Dataview | Live queries powering the [[Home]] dashboard |
| Tasks | `- [ ]` tasks with due dates; the `tasks` blocks on Home |
| Homepage | Opens [[Home]] on launch |
| Calendar | Sidebar calendar — click a date to open its note |
| NLDates | `@today`, `@tomorrow`, `@next monday` in note bodies |
| Iconize | Folder + note icons and colors |
| Style Settings | Catppuccin theme tweak panel |
| Linter | On-save tidy of frontmatter and markdown |
| Omnisearch | Full-text fuzzy search across the vault |
| Excalidraw | Hand-drawn diagrams |
| Tag Wrangler | Rename / merge tags from the sidebar |
| Auto Link Title | Paste a URL → it fetches the page title for the link |

## Reseeding from the dotfiles repo

This vault's `.obsidian/` overlay, templates, and this guide are seeded from
the dotfiles repo on `chezup` — but **only when absent**. Existing files are
never overwritten, so any tweak you make in Obsidian sticks. To pull a fresh
canonical copy of a seeded file, delete it from the vault and run `chezup`;
to update a plugin, delete its folder under `.obsidian/plugins/<id>/` and run
`chezup`.
