<%*
const subject = await tp.system.prompt("Meeting subject");
const filename = `${tp.date.now("YYYY-MM-DD")} ${subject}`;
await tp.file.rename(filename);
%>---
type: meeting
icon: LiCalendarClock
iconColor: "#ef9f76"
created: <% tp.date.now("YYYY-MM-DD HH:mm") %>
date: <% tp.date.now("YYYY-MM-DD") %>
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
