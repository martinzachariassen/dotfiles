<%*
const titleInput = await tp.system.prompt("Note title");
await tp.file.rename(titleInput);
%>---
type: note
icon: LiFileText
iconColor: "#838ba7"
aliases: []
created: <% tp.date.now("YYYY-MM-DD HH:mm") %>
status:
tags: []
related: []
---
# <% titleInput %>


