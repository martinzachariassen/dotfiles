<%*
const titleInput = await tp.system.prompt("Title");
const category = await tp.system.suggester(["book", "article", "paper", "video", "podcast"], ["book", "article", "paper", "video", "podcast"], true, "Source type?");
const status = await tp.system.suggester(["to-read", "reading", "done"], ["to-read", "reading", "done"], true, "Status?");
const domain = await tp.system.suggester(["work", "personal", "learning"], ["work", "personal", "learning"], true, "Domain?");
const domainFolder = "10 Areas/" + domain.charAt(0).toUpperCase() + domain.slice(1);
if (!tp.app.vault.getAbstractFileByPath(domainFolder)) await tp.app.vault.createFolder(domainFolder);
await tp.file.move(`${domainFolder}/${titleInput}`);
%>---
type: reading
icon: LiBookOpen
iconColor: "#ca9ee6"
aliases: []
created: <% tp.date.now("YYYY-MM-DD HH:mm") %>
category: <% category %>
domain: <% domain %>
author:
url:
status: <% status %>
rating:
started:
finished:
tags: [reading]
related: []
---
# <% titleInput %>

> <% category %>  ·  by   ·  status: <% status %>

## Summary

> Why it matters, in one line.

## Highlights
-

## Notes

## Takeaways
-
