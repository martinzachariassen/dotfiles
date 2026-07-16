<%*
const title = await tp.system.prompt("Project name");
const domain = await tp.system.suggester(["work", "personal", "learning"], ["work", "personal", "learning"], true, "Domain?");
const priority = await tp.system.suggester(["high", "medium", "low"], ["high", "medium", "low"], true, "Priority?");
const domainFolder = "10 Areas/" + domain.charAt(0).toUpperCase() + domain.slice(1);
if (!tp.app.vault.getAbstractFileByPath(domainFolder)) await tp.app.vault.createFolder(domainFolder);
await tp.file.move(`${domainFolder}/${title}`);
%>---
type: project
icon: LiFolderKanban
iconColor: "#a6d189"
aliases: []
created: <% tp.date.now("YYYY-MM-DD HH:mm") %>
status: active
domain: <% domain %>
priority: <% priority %>
started: <% tp.date.now("YYYY-MM-DD") %>
target:
area:
repo:
tags: [project]
related: []
---
# <% title %>

> Status: active  ·  <% domain %>  ·  priority <% priority %>

## Goal

> One sentence: what does "done" look like?

## Why now

## Next actions
- [ ]

## Open questions
-

## Decisions
-

## Log
- <% tp.date.now("YYYY-MM-DD") %> — created
