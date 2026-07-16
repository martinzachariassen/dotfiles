<%*
const title = tp.file.title;
const week = moment(title, "YYYY-[W]WW");
const start = week.clone().startOf('isoWeek');
const end = week.clone().endOf('isoWeek');
%>---
type: weekly
icon: LiCalendarRange
iconColor: "#8caaee"
week: <% title %>
created: <% tp.date.now("YYYY-MM-DD HH:mm") %>
range: <% start.format("YYYY-MM-DD") %> → <% end.format("YYYY-MM-DD") %>
month: "[[<% start.format('YYYY-MM') %>]]"
status: open
tags: [weekly, review]
---
# Week <% title %>

> <% start.format("MMM D") %> – <% end.format("MMM D, YYYY") %>  ·  [[<% start.format('YYYY-MM') %>|month]]

## What got done

```dataview
LIST FROM "99 Meta/Daily"
WHERE type = "daily" AND date >= date("<% start.format("YYYY-MM-DD") %>") AND date <= date("<% end.format("YYYY-MM-DD") %>")
SORT date ASC
```

## Wins

## Drag

## Carrying forward

## Next week's focus
