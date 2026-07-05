<%*
const title = tp.file.title;
const m = moment(title, "YYYY-MM-DD");
%>---
type: daily
icon: LiCalendarDays
iconColor: "#8caaee"
date: <% title %>
created: <% tp.date.now("YYYY-MM-DD HH:mm") %>
week: "[[<% m.format('YYYY-[W]WW') %>]]"
tags: [daily]
---
# <% title %> · <% m.format("dddd") %>

> [[<% m.clone().subtract(1, 'd').format("YYYY-MM-DD") %>|← yesterday]] · [[<% m.clone().add(1, 'd').format("YYYY-MM-DD") %>|tomorrow →]] · [[<% m.format('YYYY-[W]WW') %>|week]]

## Focus
-

## Tasks
- [ ]

```tasks
not done
due before <% m.clone().add(1, 'd').format("YYYY-MM-DD") %>
sort by priority
```

## Log

## Notes
