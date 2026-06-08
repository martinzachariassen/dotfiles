<%*
const name = await tp.system.prompt("Area name");
const domain = await tp.system.suggester(["work", "personal", "learning"], ["work", "personal", "learning"], true, "Domain?");
await tp.file.rename(name);
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
TABLE status, priority FROM "20 Projects"
WHERE type = "project" AND contains(related, this.file.link)
SORT status ASC
```

## Routines & rituals
-

## Notes
