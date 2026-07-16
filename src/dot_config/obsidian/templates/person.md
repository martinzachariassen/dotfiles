<%*
const name = await tp.system.prompt("Person's name");
const domain = await tp.system.suggester(["work", "personal"], ["work", "personal"], true, "Domain?");
const domainFolder = "10 Areas/" + domain.charAt(0).toUpperCase() + domain.slice(1);
if (!tp.app.vault.getAbstractFileByPath(domainFolder)) await tp.app.vault.createFolder(domainFolder);
await tp.file.move(`${domainFolder}/${name}`);
%>---
type: person
icon: LiUser
iconColor: "#ca9ee6"
aliases: []
created: <% tp.date.now("YYYY-MM-DD HH:mm") %>
domain: <% domain %>
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
