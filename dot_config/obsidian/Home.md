---
tags: [home]
---
# Home

> [!tip]+ New here? Read the **[[Vault Guide]]**
> Folder layout, capture flow, hotkeys, where things go. This dashboard
> is yours to edit — it's only seeded once.
>
> Quick keys: `⌘⇧N` capture · `⌘⇧T` daily · `⌘⇧W` weekly · `⌘⇧I` insert template · `⌘O` find · `⌘P` commands

## Today

Hit `⌘⇧T` for today's daily, `⌘⇧W` for this week. Periodic Notes creates
them under `10 Daily/YYYY/` on first open.

## Inbox to process

```dataview
LIST file.cday
FROM "00 Inbox"
WHERE !contains(file.name, "_README")
SORT file.cday DESC
LIMIT 15
```

## Active projects

```dataview
TABLE WITHOUT ID file.link AS Project, domain, status, file.mtime AS "Last touched"
FROM "20 Projects"
WHERE !contains(file.folder, "_templates") AND (status = "active" OR !status) AND !contains(file.name, "_README")
SORT file.mtime DESC
LIMIT 15
```

## Areas — what you maintain

```dataview
TABLE WITHOUT ID file.link AS Area, file.folder AS Folder, file.mtime AS "Last touched"
FROM "30 Areas"
WHERE !contains(file.name, "_README")
SORT file.mtime DESC
LIMIT 15
```

## Recent resources

```dataview
LIST file.mtime
FROM "40 Resources"
WHERE !contains(file.name, "_README")
SORT file.mtime DESC
LIMIT 10
```

## Tasks

### Overdue

```tasks
not done
due before today
sort by due
limit 15
```

### Coming up — next 7 days

```tasks
not done
due after yesterday
due before in 8 days
sort by due
limit 20
```

## Recently edited

```dataview
LIST file.mtime
WHERE !contains(file.folder, "_templates") AND !contains(file.folder, "50 Archive") AND !contains(file.name, "_README") AND file.name != "Home" AND file.name != "Vault Guide"
SORT file.mtime DESC
LIMIT 15
```
