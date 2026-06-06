---
tags: [meta, guide]
---
# Vault Guide

How this vault is organized and how to work in it. Linked from
[[Home]] — open `⌘O → Vault Guide` to jump back any time.

## The PARA layout

Folders are sorted by **actionability**, not topic. Pick the folder by
asking _"how soon will I act on this?"_.

| Folder | What goes there | Question |
|---|---|---|
| `00 Inbox` | Unsorted captures, ideas, links | "I'll deal with it later" |
| `10 Daily` | Daily + weekly periodic notes | (auto, see below) |
| `20 Projects` | Work with an outcome + end date | "I want to finish X by Y" |
| `30 Areas` | Ongoing responsibilities, no deadline | "I maintain X indefinitely" |
| `40 Resources` | Reference material, snippets, reading | "I might want this again" |
| `50 Archive` | Finished projects, retired areas | "Done. Keep for search." |
| `99 Meta` | Templates, attachments, this guide | (vault plumbing) |

Each non-meta folder has a `_README.md` with its own scoping rules — the
underscore keeps it pinned at the top of the file explorer.

## Capture flow

| Keystroke | What happens |
|---|---|
| `⌘⇧N` | **QuickAdd → Capture to inbox**. Prompts for a title, drops a timestamped note in `00 Inbox/` |
| `⌘⇧T` | Open today's daily note (Periodic Notes creates it from `daily.md` if missing) |
| `⌘⇧W` | Open this week's weekly note |
| `⌘⇧I` | Insert any template into the current note (Templater picker) |
| `⌘O` | Quick switcher — find any note by name |
| `⌘P` | Command palette — every action lives here |
| `⌘⇧F` | Global search |
| `⌘⌥F` | Search inside the file explorer |
| `⌘⌥←` / `⌘⌥→` | Toggle left / right sidebars |

The weekly review is when you process `00 Inbox/` and move things into
their permanent home in `20`/`30`/`40` — or into `50 Archive/` if they're
already done.

## Templates

All templates live in `99 Meta/_templates/` and use **Templater**
syntax (`<%* … %>`). Anything created in a folder that has a folder-template
mapping, or that contains Templater syntax, is processed automatically on
creation.

| Template | Used by | What it sets |
|---|---|---|
| `inbox.md` | QuickAdd `⌘⇧N` → `00 Inbox/` | `type: inbox`, timestamped filename |
| `daily.md` | Periodic Notes `⌘⇧T` → `10 Daily/YYYY/` | `type: daily`, prev/next links, today's tasks |
| `weekly.md` | Periodic Notes `⌘⇧W` → `10 Daily/YYYY/` | `type: weekly`, Mon–Sun range, daily roll-up |
| `project.md` | Insert with `⌘⇧I` → `20 Projects/` | `type: project`, prompts for `domain` (work/personal) |
| `meeting.md` | Insert with `⌘⇧I` | `type: meeting`, attendees, action items |
| `person.md` | Insert with `⌘⇧I` → `40 Resources/42 People/` | `type: person`, 1:1 log |

To add a new template: drop a `.md` file into `99 Meta/_templates/` with
`<%* … %>` Templater syntax at the top. It shows up in the picker
immediately.

## Frontmatter conventions

Every note carries a `type:` property so dashboards can filter
reliably. Projects also carry `domain: work | personal` so work and
personal live flat in the same folder but split cleanly in views.

```yaml
---
type: project        # inbox | daily | weekly | project | meeting | person | …
status: active       # active | paused | done  (projects only)
domain: work         # work | personal           (projects only)
started: 2026-06-06  # YYYY-MM-DD
tags: [project]
---
```

## Where do I put this?

A quick decision tree for a new note:

1. **Is it half-baked / unsorted?** → `00 Inbox/`. Process at the next
   weekly review.
2. **Has it got an outcome and a finish line?** → `20 Projects/`,
   own subfolder, use the `project` template.
3. **Is it a thing I'll keep tending indefinitely?** → `30 Areas/`,
   under `31 Work/` / `32 Personal/` / `33 Learning/`.
4. **Is it reference material I might want again?** → `40 Resources/`,
   under `41 Tech/` / `42 People/` / `43 Reading/`.
5. **Is it a person I want to track?** → `40 Resources/42 People/`,
   `person` template.
6. **Is it a meeting?** → wherever its project lives (`20 Projects/<x>/`)
   or `40 Resources/42 People/` for 1:1s. Use the `meeting` template.
7. **Is it done / no longer active?** → `50 Archive/`. Don't delete —
   future-you may want the context.

## Plugins in play

| Plugin | What it does |
|---|---|
| Templater | Dynamic templates (`<%* … %>`) |
| QuickAdd | `⌘⇧N` capture flow |
| Periodic Notes | Daily / weekly notes lifecycle |
| Dataview | Live queries powering the Home dashboard |
| Tasks | `- [ ]` tasks with due dates, the `tasks` code blocks on Home |
| Homepage | Opens `[[Home]]` on launch |
| Calendar | Sidebar calendar — click a date to open its daily note |
| NLDates | `@today`, `@tomorrow`, `@next monday` in note bodies |
| Style Settings | Theme tweak panel for Catppuccin |
| Linter | On-save tidy of frontmatter and markdown |
| Omnisearch | Full-text fuzzy search across the vault |
| Excalidraw | Hand-drawn diagrams |
| Icon Folder | Per-folder icons in the file explorer |
| Tag Wrangler | Tag rename / merge from the sidebar |
| Auto Link Title | Paste a URL → it auto-fetches the title for the link text |

## Reseeding from the dotfiles repo

This vault's `.obsidian/` overlay, templates, and this guide are seeded
from the dotfiles repo on `chezup` — but **only when absent**.
Existing files in the vault are never overwritten, so any tweak you make
in the Obsidian UI sticks.

To pull a fresh canonical copy of a seeded file: delete it from the
vault, then run `chezup`. To pull a plugin update: delete its folder
under `.obsidian/plugins/<id>/` and run `chezup`.
