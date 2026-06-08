<%*
const title = tp.file.title;
const filename = `${tp.date.now("YYYY-MM-DD HHmm")} ${title}`;
await tp.file.rename(filename);
%>---
type: inbox
icon: LiInbox
iconColor: "#e78284"
created: <% tp.date.now("YYYY-MM-DD HH:mm") %>
status: unprocessed
tags: [inbox]
related: []
---
# <% title %>


