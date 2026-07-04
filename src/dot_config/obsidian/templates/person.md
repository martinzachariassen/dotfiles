<%*
const name = await tp.system.prompt("Person's name");
await tp.file.rename(name);
%>---
type: person
icon: LiUser
iconColor: "#ca9ee6"
aliases: []
created: <% tp.date.now("YYYY-MM-DD HH:mm") %>
role:
team:
company:
email:
first-met: <% tp.date.now("YYYY-MM-DD") %>
tags: [person]
related: []
---
# <% name %>

> **Role:**   ·   **Team / company:**

## Context

## Topics they care about
-

## 1:1 history
- <% tp.date.now("YYYY-MM-DD") %> —
