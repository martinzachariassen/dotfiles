<%*
const title = tp.file.title;
%>---
type: daily
date: <% title %>
tags: [daily]
---
# <% title %> · <% moment(title, "YYYY-MM-DD").format("dddd") %>

> [[<% moment(title, "YYYY-MM-DD").subtract(1, 'd').format("YYYY-MM-DD") %>|← yesterday]] · [[<% moment(title, "YYYY-MM-DD").add(1, 'd').format("YYYY-MM-DD") %>|tomorrow →]]

## Focus
-

## Tasks
- [ ]

```tasks
not done
due before <% moment(title, "YYYY-MM-DD").add(1, 'd').format("YYYY-MM-DD") %>
sort by priority
```

## Log

## Notes
