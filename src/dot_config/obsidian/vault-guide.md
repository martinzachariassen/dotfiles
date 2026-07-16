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

> [!tip] Your daily loop is 5 keys
> Everything else in this guide is optional depth. Day to day you only need:
> **`⌘⇧N`** capture · **`⌘⇧M`** file this note · **`⌘⇧T`** today's note ·
> **`⌘O`** find anything · **`⌘P`** every other command. Learn these five and
> the vault runs itself.

> [!tip] The 10-second version
> **Capture** with `⌘⇧N` → everything lands in `00 Inbox`. **File** it with
> `⌘⇧M` (**File this…** → pick Work / Personal / Learning / Archive) — do a
> sweep at your weekly review, or whenever the inbox nags. To create a typed
> note directly, use one of the **QuickAdd "New …" commands** (`⌘P` → "New
> project", "New area", "New person", "New reading item", "New meeting") —
> each prompts for a domain and files itself there automatically.

## The layout

Four folders, one question each: *what kind of note is this* is a
`type` property, not a folder — the folder only answers *whose life is this
part of*.

| Folder | What goes there | The question |
|---|---|---|
| `00 Inbox` | Unsorted captures, ideas, links | "I'll deal with it later" |
| `10 Areas` | Everything active: projects, ongoing responsibilities, people, reading, reference — split into `Work` / `Personal` / `Learning` | "Whose life is this part of?" |
| `20 Archive` | Finished projects, retired areas | "Done. Keep for search." |
| `99 Meta` | Templates, scripts, attachments, `Daily/` notes, this guide | (vault plumbing) |

Each top-level folder has a `_README.md` explaining its scope. The leading
underscore on `_templates`/`_scripts`/`_attachments` pins them to the top of
the file list.

## Keyboard shortcuts

| Key | What happens |
|---|---|
| `⌘⇧N` | **Capture to inbox** (QuickAdd) — prompts for a title, drops a **titled** note in `00 Inbox/` (the topic is the name; time is kept in `created`) |
| `⌘⇧M` | **File this…** (QuickAdd) — pops a domain menu (💼 Work / 🏠 Personal / 🎓 Learning / 🗄 Archive), an optional type picker, and an optional topic-tag picker, then moves the note there, sets `domain` / `type` / `tags`, and fixes backlinks |
| `⌘⇧T` | Open **today's daily** note (created from `daily.md` if missing) |
| `⌘⇧W` | Open **this week's** weekly note |
| `⌘⇧I` | **Insert a template** into the current note (Templater picker) |
| `⌘O` | **Quick switcher** — find any note by name |
| `⌘P` | **Command palette** — every command lives here, including the "New project / area / person / reading item / meeting" QuickAdd commands |
| `⌘⌥F` | Search within the file explorer |
| `⌘⌥←` / `⌘⌥→` | Toggle the left / right sidebar |

Monthly notes have no default key — open one via `⌘P → "Open monthly note"`.

## Creating notes

There are three ways a note gets the right template and properties:

1. **Inbox auto-template.** Make a new note *inside* `00 Inbox` and the
   `inbox` template runs automatically — the only folder that still does this.
2. **QuickAdd commands.** `⌘P` (or the mobile toolbar) → **New project**,
   **New area**, **New person**, **New reading item**, or **New meeting**.
   Each prompts for a domain (and any type-specific fields) and moves the
   finished note into `10 Areas/<Domain>/` for you — one step, same as
   before, just not tied to which folder you happened to click "new note" in.
3. **Periodic Notes.** `⌘⇧T` / `⌘⇧W` (and monthly via the palette) create
   dated notes in `99 Meta/Daily/YYYY/` from their templates.

For a generic, typeless note, press `⌘⇧I` anywhere and pick `note`.

## Templates

All templates live in `99 Meta/_templates/` and use **Templater** syntax
(`<%* … %>`). Each one sets a `type`, an `icon`, a `created` stamp, and
type-specific properties.

| Template | How you get it | Sets up |
|---|---|---|
| `inbox` | `⌘⇧N`, or new note in `00 Inbox` | Titled capture (time in `created`) |
| `daily` | `⌘⇧T` | Day note: prev/next nav, today's tasks, log |
| `weekly` | `⌘⇧W` | Week note: Mon–Sun range, daily roll-up |
| `monthly` | `⌘P → Open monthly note` | Month note: rolls up the weeklies |
| `project` | QuickAdd: **New project** | Domain-filed. Goal, next actions, decisions, log |
| `area` | QuickAdd: **New area** | Domain-filed. Standards, focus, related projects |
| `person` | QuickAdd: **New person** | Domain-filed. Role, 1:1 history, topics |
| `reading` | QuickAdd: **New reading item** | Domain-filed. Author, source, status, rating, highlights |
| `meeting` | QuickAdd: **New meeting** | Domain-filed. Agenda, notes, decisions, action items |
| `note` | `⌘⇧I` | Lightweight generic note, no domain |

To add a template, drop a `.md` file with `<%* … %>` at the top into
`99 Meta/_templates/`. It appears in the `⌘⇧I` picker immediately — wire it
up as a one-step QuickAdd command the same way the others are if you want it
to self-file.

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
domain: work           # work | personal | learning
priority: high         # high | medium | low
started: 2026-06-08    # dates render as a picker
target:                # deadline
related: []            # links to related notes
tags: [project]
---
```

Common fields by type: **project** → `status, domain, priority, started,
target, area, repo`; **reading** → `category, author, url, status, rating,
started, finished, domain`; **person** → `role, team, company, email,
first-met, domain`; **area** → `domain, status, review`; **meeting** →
`date, attendees, project, status, domain`.

`repo` — a GitHub/GitLab URL on a project, tech-resource, or dev note; click
through from the note or the Projects Base to jump straight to the code.
Optional, not auto-set by any template except `project`.

### Two axes for finding things

You don't tag by hand — filing does it. Two complementary properties make any
note findable:

- **`domain`** (`work` / `personal` / `learning`) — the *whose-life* axis.
  Prompted by nearly every typed note's QuickAdd command, and also settable
  at `⌘⇧M`. Filter on it in Dataview: `WHERE domain = "work"`.
- **`tags`** — the *what-it's-about* axis. Pick from the curated list in the
  **File this…** step (`dev`, `infra`, `career`, `learning`, `reading`,
  `finance`, `health`, `idea`). They render as chips and drive the **Tag pane**
  (left sidebar → tag icon) — click `#dev` to see everything dev-related across
  every folder. Autocomplete still lets you add one by hand in the property field.

To change the tag menu, edit the one-line `TOPICS` list at the top of
`99 Meta/_scripts/file-note.js` — the picker updates on the next file. Keep it
short: a tight, reused vocabulary is what makes the tag tree worth browsing; a
sprawling one is just noise.

## Icons & colors

- **Folders** are colored by Iconize: Inbox red, Areas teal (with Work/
  Personal/Learning subfolders in the same teal family), Archive/Meta gray,
  and Daily blue (nested under Meta).
- **Notes** show a per-type icon by the title, driven by the `icon` /
  `iconColor` frontmatter that templates add for you.
- To change one by hand: right-click a folder/note → **Change icon** /
  **Change color**, or edit the `icon` property. Lucide IDs are `Li` +
  PascalCase (e.g. `LiBookOpen`).

## Where do I put this?

From an open inbox note, `⌘⇧M` (**File this…**) does the rest for you — pick
a domain (and optionally re-type the note) and it moves the note and fixes
any backlinks. This list is the mental model behind that:

1. **Half-baked / unsorted?** → `00 Inbox`. Sort it at the weekly review.
2. **Anything else — a project, an ongoing responsibility, a person, a
   reading-list item, a reference note?** → `10 Areas/Work`, `Personal`, or
   `Learning`, whichever domain it belongs to. The `type` property (not the
   folder) says what kind of note it is.
3. **Done / inactive?** → `20 Archive`. Move, don't delete.

## Weekly review

Once a week: open this week's note (`⌘⇧W`), empty `00 Inbox` — work the
**Inbox to process** list on [[Home]] top-down, hitting `⌘⇧M` on each — glance
at **Active projects** and **Not linked from anywhere**, and set next week's
focus. Monthly, do the same one level up with the monthly note.

## Plugins in play

| Plugin | What it does |
|---|---|
| Templater | Dynamic templates (`<%* … %>`) |
| QuickAdd | `⌘⇧N` capture flow, `⌘⇧M` "File this…" mover, and the "New …" one-step template commands |
| Periodic Notes | Daily / weekly / monthly note lifecycle |
| Dataview | Live queries powering the [[Home]] dashboard |
| Tasks | `- [ ]` tasks with due dates; the `tasks` blocks on Home |
| Homepage | Opens [[Home]] on launch |
| Iconize | Folder + note icons and colors |
| Minimal Theme Settings | Color scheme (Catppuccin), contrast, and other Minimal theme options |
| Style Settings | General CSS-variable tweak panel other plugins hook into |
| Linter | On-save tidy of frontmatter and markdown |
| Code Styler | Line numbers, language label, and copy button on code fences |
| Auto Link Title | Paste a URL → it fetches the page title for the link |

Oversight comes from **core Bases** (no plugin): [[Projects.base|Projects &
Areas]] is a live table/board of open projects, areas, and the inbox — sort or
group it however you like. Linked from [[Home]].

## On mobile

Capture and filing both work on the phone — they're commands, not desktop
shortcuts. Add them to the mobile toolbar once: **Settings → Mobile → Manage
toolbar options** (or the wrench in the toolbar) → add **"QuickAdd: Capture
to inbox"**, **"QuickAdd: File this…"**, and **"Periodic Notes: Open today's
daily note"**. Until you do, all three are reachable from the command palette.

For even faster capture, an iOS Shortcut can help — two options, depending on
how much you're willing to trade:

- **Fast, still opens the app briefly**: a Shortcut that asks for input, then
  opens `obsidian://new?vault=<vault name>&name=<input>`. This lands the note
  straight in `00 Inbox` (the vault's default new-note location) but does
  briefly foreground Obsidian — there's no true headless capture via the URI
  scheme.
- **True headless capture**: a Shortcut that writes a `.md` file directly
  into the iCloud-synced `00 Inbox/` folder, never opening Obsidian at all.
  The tradeoff: it bypasses Templater, so the note won't get its `type` /
  `icon` / `created` stamp until you next open it in the app.

Pick whichever tradeoff suits you — both just create a titled note in Inbox.

## Backups

Vault content is synced by iCloud, which protects against device loss but
**not** against a bad delete or edit spreading to every device. Versioned
backup (e.g. via Obsidian Git, auto-committing to a private repo) is
deliberately not set up right now — it adds a plugin and a bit of setup for a
problem you haven't hit yet. If you want it later, it's straightforward to
add: install the plugin, point it at a private remote, and it handles the
rest.

## Reseeding from the dotfiles repo

This vault's `.obsidian/` overlay, templates, and this guide are seeded from
the dotfiles repo on `chezup` — but **only when absent**. Existing files are
never overwritten, so any tweak you make in Obsidian sticks. To pull a fresh
canonical copy of a seeded file, delete it from the vault and run `chezup`;
to update a plugin, delete its folder under `.obsidian/plugins/<id>/` and run
`chezup`.
