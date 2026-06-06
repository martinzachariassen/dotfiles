<%*
const title = tp.file.title;
const filename = `${tp.date.now("YYYY-MM-DD HHmm")} ${title}`;
await tp.file.rename(filename);
%>---
type: inbox
captured: <% tp.date.now("YYYY-MM-DD HH:mm") %>
tags: [inbox]
---
# <% title %>

