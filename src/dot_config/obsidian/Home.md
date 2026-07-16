---
type: home
icon: LiHouse
iconColor: "#8caaee"
tags: [home]
---
# Home

> [!tip]+ Daily loop — five keys
> **Capture** `⌘⇧N`  ·  **File** `⌘⇧M`  ·  **Daily** `⌘⇧T`  ·  **Find** `⌘O`  ·  **Commands** `⌘P`
>
> More: **Weekly** `⌘⇧W` · **Insert template** `⌘⇧I`   —   **[[Vault Guide|📖 Guide]]**  ·  **[[Projects.base|📊 Projects & Areas]]**

## 📥 Inbox to process
*Open the oldest → `⌘⇧M` files it → it drops off the list. Goal: empty.*

```dataview
TABLE WITHOUT ID file.link AS Note, dateformat(default(created, file.ctime), "MMM d") AS Captured
FROM "00 Inbox"
WHERE !contains(file.name, "_README")
SORT default(created, file.ctime) ASC
LIMIT 50
```

## ✅ Tasks

**Overdue**

```tasks
not done
due before today
sort by due
limit 15
```

**Next 7 days**

```tasks
not done
due after yesterday
due before in 8 days
sort by due
limit 20
```

## 🚀 Active projects
*Work with a finish line. Sortable board of projects **and** areas → **[[Projects.base|📊 Projects & Areas]]**.*

```dataview
TABLE WITHOUT ID file.link AS Project, domain AS Domain, priority AS Priority, dateformat(file.mtime, "MMM d") AS Touched
FROM "10 Areas"
WHERE type = "project" AND (status = "active" OR !status) AND !contains(file.name, "_README")
SORT file.mtime DESC
LIMIT 15
```

## 🔗 Not linked from anywhere
*Zero inlinks — link it from a project, area, or MOC so it doesn't vanish into search.*

```dataview
LIST
FROM "10 Areas"
WHERE length(file.inlinks) = 0 AND !contains(file.name, "_README") AND file.name != "Home" AND file.name != "Vault Guide"
SORT file.mtime DESC
LIMIT 10
```

---
### Browse & jump back in

#### 📖 Currently reading

```dataview
TABLE WITHOUT ID file.link AS Title, author AS Author, category AS Type
FROM "10 Areas"
WHERE type = "reading" AND status = "reading"
SORT file.mtime DESC
LIMIT 10
```

#### 🕐 Recently edited

```dataview
LIST dateformat(file.mtime, "MMM d, HH:mm")
WHERE !contains(file.folder, "_templates") AND !contains(file.folder, "20 Archive") AND !contains(file.folder, "00 Inbox") AND !contains(file.name, "_README") AND file.name != "Home" AND file.name != "Vault Guide"
SORT file.mtime DESC
LIMIT 12
```
