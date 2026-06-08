---
type: home
icon: LiHouse
iconColor: "#8caaee"
tags: [home]
---
# Home

> [!tip]+ Quick keys
> **Capture** `⌘⇧N`  ·  **Daily** `⌘⇧T`  ·  **Weekly** `⌘⇧W`  ·  **Insert template** `⌘⇧I`  ·  **Find** `⌘O`  ·  **Commands** `⌘P`
>
> New here? Take the full tour → **[[Vault Guide]]**

---

## Inbox to process
*Captures waiting to be filed. Clear these at your weekly review.*

```dataview
TABLE WITHOUT ID file.link AS Note, dateformat(file.ctime, "MMM d, HH:mm") AS Captured
FROM "00 Inbox"
WHERE !contains(file.name, "_README")
SORT file.ctime DESC
LIMIT 15
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

## Active projects
*Open work with an outcome and an end date.*

```dataview
TABLE WITHOUT ID file.link AS Project, domain AS Domain, priority AS Priority, dateformat(file.mtime, "MMM d") AS "Touched"
FROM "20 Projects"
WHERE type = "project" AND (status = "active" OR !status) AND !contains(file.name, "_README")
SORT file.mtime DESC
LIMIT 15
```

## Areas you maintain
*Ongoing responsibilities — no finish line.*

```dataview
TABLE WITHOUT ID file.link AS Area, domain AS Domain, review AS Review
FROM "30 Areas"
WHERE type = "area" AND !contains(file.name, "_README")
SORT file.name ASC
LIMIT 15
```

## Currently reading

```dataview
TABLE WITHOUT ID file.link AS Title, author AS Author, category AS Type
FROM "40 Resources/43 Reading"
WHERE type = "reading" AND status = "reading"
SORT file.mtime DESC
LIMIT 10
```

## Recently edited

```dataview
LIST dateformat(file.mtime, "MMM d, HH:mm")
WHERE !contains(file.folder, "_templates") AND !contains(file.folder, "50 Archive") AND !contains(file.name, "_README") AND file.name != "Home" AND file.name != "Vault Guide"
SORT file.mtime DESC
LIMIT 15
```
