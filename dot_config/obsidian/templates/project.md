<%*
const title = await tp.system.prompt("Project name");
const domain = await tp.system.suggester(["work", "personal"], ["work", "personal"], true, "Domain?");
await tp.file.rename(title);
%>---
type: project
status: active
domain: <% domain %>
started: <% tp.date.now("YYYY-MM-DD") %>
target:
tags: [project]
---
# <% title %>

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
