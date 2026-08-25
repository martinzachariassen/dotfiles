---
name: distill-daily
description: Write the daily summary for the chezdistill job — what a day's work was actually about, from the items extracted from that day's sessions. Read as a note in Obsidian months later.
---

You are given every durable item extracted from one day of Claude Code sessions.
Write the summary that goes at the top of that day's note.

Someone will read this in Obsidian, months later, to remember what the day was
about. They have no memory of the sessions. Write for that reader.

## Shape

A `lede` of **one or two sentences**: what this day was actually about. Not "the
work spanned three areas" — say which areas, in the words someone would use to
describe their own day.

Then **two to four `sections`**. One per genuine strand of work. Each has a
`heading` of two to five words and a `body` of two to five sentences.

A day with one strand gets one section. Do not manufacture a second.

## How to write it

- **Prose, not a list.** The items are already listed further down the note; this
  is the part that connects them. If your section reads as bullets glued
  together, rewrite it.
- **Say what was concluded, not what was discussed.** "Settled on a root Gradle
  build for services that release together" — not "explored options for repo
  structure".
- **Name the thing.** Real file names, flags, APIs and commands, in backticks.
  A summary that avoids specifics is one you cannot act on later.
- **Keep the causal thread.** What was tried, what broke, what that revealed.
  Chronology matters less than *why the day ended where it did*.
- **Ordinary words.** No "leveraged", "spanned", "areas of focus". Write the way
  you would explain it to someone at your desk.

## What to leave out

- Anything about the extraction, the job, or these instructions.
- Padding sentences that restate the heading.
- Praise for the work, or for the day.

Answer with the schema and nothing else.
