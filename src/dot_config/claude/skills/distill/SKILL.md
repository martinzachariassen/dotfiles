---
name: distill
description: Extract durable, reusable lessons from a Claude Code session transcript — decisions, preferences, learnings, answered questions, open threads and gotchas. Used by the chezdistill nightly job and invocable by hand to review a conversation.
---

You read one Claude Code session and extract what is worth keeping. Answer with
the schema and nothing else.

Two horizons, and they want different things. Most items are standing
instructions for a future session: those must still be true a month from now. But
`decisions` and `open_threads` are about what was settled and what is still owed —
a decision does not stop mattering because it was only made once, and an open
thread matters *most* the day after. Do not apply the "still true in a month"
filter to those two.

## What counts

- **decisions** — a choice that was actually settled, and that constrains future
  work. "We will use X" — not "we could use X". Record what was chosen **and what
  it was chosen over**: the rejected alternative and the reason are the half that
  is impossible to reconstruct later. Emit these even when the session produced
  only one.
- **preferences** — how the user wants work done, stated or clearly corrected
  into. Style, tooling, tone, process.
- **learnings** — a fact about the world or the codebase that was discovered and
  turned out to matter.
- **questions_answered** — a question that was open and now is not. Record the
  answer, not the question.
- **open_threads** — something left undone at the end of the session: explicitly
  deferred, blocked on someone else, a known defect not yet fixed, a follow-up
  that was named but not started. Be generous here — these are cheap to discard
  and expensive to forget, and a session that ended mid-task almost always has
  one. Write it so it still makes sense with no memory of the session: what is
  unfinished, and what the next step is.
- **gotchas** — a trap that cost time, and the shape of the trap. These are the
  most valuable items; they are what a future session would otherwise re-learn.

## What never counts

- Anything the repository already documents. If it is in a README, a CLAUDE.md or
  a config file, it does not need to be in memory too.
- One-off details: a specific file path, a line number, a single command run once,
  a transient error that was fixed and will not recur.
- Restatements of general knowledge. "Tests should pass" is not a learning.
- Anything about *this* extraction task.
- **Never reproduce secrets.** Tokens, keys, credentials, signing material,
  `.env` values, connection strings. If a lesson depends on one, describe the
  shape of the value, never the value.

## How to write an item

- `text` — **at most 25 words.** This is the rule itself, and it is loaded into
  every future session, so every word is paid for forever. Write the instruction,
  not the explanation. It will be read months later with no surrounding context,
  so it must not refer to "the above", "this file", or "that error".
- `detail` — the full explanation, as long as it needs to be: why this is true,
  what goes wrong without it, the specific API or flag involved. This is stored
  in a topic note that is read only on demand, so length costs nothing here.
  Everything you were tempted to cram into `text` belongs in this field.
- `topic` — a short noun that groups related items: `Shell`, `Chezmoi`, `Git`,
  `Testing`. Reuse an existing-sounding topic rather than inventing a variant.
- `evidence` — a short quote or paraphrase from the transcript showing this was
  actually settled, not merely mentioned. An item you cannot evidence is an item
  you should not emit.
- `confidence` — `high` when it was explicitly stated or decided, `medium` when
  it was clearly implied, `low` when you are inferring. Prefer emitting fewer
  items to padding with `low`.

## Calibration

A typical productive session yields **two to five** items, plus any decisions and
open threads it produced — those are not counted against that budget. A session that was
mostly mechanical yields **none**, and emitting none is a correct answer — the
job that calls you will skip the session entirely. Do not pad.

Duplicate-sounding items across sessions are fine and expected: the caller counts
how many distinct sessions an item appears in, and only items seen at least twice
are ever promoted into the persistent instructions. Write the item the same way
each time so that counting works — stable phrasing is more useful than variety.
