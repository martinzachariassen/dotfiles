<%*
const name = await tp.system.prompt("Area name");
const domain = await tp.system.suggester(["work", "personal", "learning"], ["work", "personal", "learning"], true, "Domain?");
const domainFolder = "10 Areas/" + domain.charAt(0).toUpperCase() + domain.slice(1);
if (!tp.app.vault.getAbstractFileByPath(domainFolder)) await tp.app.vault.createFolder(domainFolder);
await tp.file.move(`${domainFolder}/${name}`);
%>---
type: area
icon: LiLayers
iconColor: "#81c8be"
aliases: []
created: <% tp.date.now("YYYY-MM-DD HH:mm") %>
domain: <% domain %>
status: active
review: weekly
tags: [area]
related: []
---
# <% name %>

> Ongoing responsibility  ·  <% domain %>  ·  review: weekly

## What good looks like

> The standard you're maintaining here.

## Current focus
-

## Related projects

```dataview
TABLE status, priority FROM "10 Areas"
WHERE type = "project" AND contains(related, this.file.link)
SORT status ASC
```

## Routines & rituals
-

## Notes
