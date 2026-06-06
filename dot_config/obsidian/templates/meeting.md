<%*
const subject = await tp.system.prompt("Meeting subject");
const filename = `${tp.date.now("YYYY-MM-DD")} ${subject}`;
await tp.file.rename(filename);
%>---
type: meeting
date: <% tp.date.now("YYYY-MM-DD") %>
attendees: []
tags: [meeting]
---
# <% subject %>

**Date:** <% tp.date.now("YYYY-MM-DD HH:mm") %>
**Attendees:**

## Agenda
-

## Notes

## Decisions
-

## Action items
- [ ]
