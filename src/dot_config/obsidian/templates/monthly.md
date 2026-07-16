<%*
const title = tp.file.title;
const month = moment(title, "YYYY-MM");
const start = month.clone().startOf('month');
const end = month.clone().endOf('month');
%>---
type: monthly
icon: LiCalendar
iconColor: "#8caaee"
month: <% title %>
created: <% tp.date.now("YYYY-MM-DD HH:mm") %>
range: <% start.format("YYYY-MM-DD") %> → <% end.format("YYYY-MM-DD") %>
status: open
tags: [monthly, review]
---
# <% month.format("MMMM YYYY") %>

> <% start.format("MMM D") %> – <% end.format("MMM D, YYYY") %>

## Weekly reviews

```dataview
LIST FROM "99 Meta/Daily"
WHERE type = "weekly" AND month = [[<% title %>]]
SORT week ASC
```

## Projects touched

```dataview
TABLE status, priority, target FROM "10 Areas"
WHERE type = "project"
SORT priority ASC
```

## Highlights

## Lowlights

## Lessons

## Next month's focus
