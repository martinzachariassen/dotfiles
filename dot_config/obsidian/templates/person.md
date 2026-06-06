<%*
const name = await tp.system.prompt("Person's name");
await tp.file.rename(name);
%>---
type: person
role:
team:
tags: [person]
---
# <% name %>

**Role:**
**Team / company:**
**First met:** <% tp.date.now("YYYY-MM-DD") %>

## Context

## Topics they care about
-

## 1:1 history
- <% tp.date.now("YYYY-MM-DD") %> —
