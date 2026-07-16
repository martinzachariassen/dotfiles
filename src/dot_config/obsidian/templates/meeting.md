<%*
const subject = await tp.system.prompt("Meeting subject");
const domain = await tp.system.suggester(["work", "personal", "learning"], ["work", "personal", "learning"], true, "Domain?");
const domainFolder = "10 Areas/" + domain.charAt(0).toUpperCase() + domain.slice(1);
if (!tp.app.vault.getAbstractFileByPath(domainFolder)) await tp.app.vault.createFolder(domainFolder);
await tp.file.move(`${domainFolder}/${subject}`);
%>---
type: meeting
icon: LiCalendarClock
iconColor: "#ef9f76"
created: <% tp.date.now("YYYY-MM-DD HH:mm") %>
date: <% tp.date.now("YYYY-MM-DD") %>
domain: <% domain %>
attendees: []
project:
status: scheduled
tags: [meeting]
related: []
---
# <% subject %>

> **<% tp.date.now("dddd, MMMM D, YYYY · HH:mm") %>**  ·  Attendees:

## Agenda
-

## Notes

## Decisions
-

## Action items
- [ ]
