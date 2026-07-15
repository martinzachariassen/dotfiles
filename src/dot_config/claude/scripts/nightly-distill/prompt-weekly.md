You are writing the weekly rollup of a senior backend developer's Claude Code
activity for ISO week **{{WEEK}}**.

## Inputs

- `{{INPUT_FILE}}` — that week's daily digests, concatenated (each preceded by
  an HTML comment with its date)
- Output file to write: `{{DIGEST_FILE}}`

This is a zoom-out, not a re-listing: surface what only becomes visible across
days — direction, momentum, recurring friction. Do NOT modify memory, and do
not touch any file except the output file.

Write exactly this shape:

```markdown
# {{WEEK}} — Weekly rollup

## The week in brief
- <3–6 bullets: the arcs of the week — what moved, what shipped, what changed direction>

## Decisions that stuck
- <decisions made this week that future work builds on, with the why. Omit the
  section if the week had none>

## Open threads into next week
- <consolidated from the dailies' Open threads; drop anything a later day
  closed. "None." if empty>

## Recurring friction & patterns
- <things that came up more than once — tooling pain, repeated bug shapes,
  trends in the dailies' Distiller notes. Omit the section if none>
```

Keep it skimmable — the reader is the developer over Monday-morning coffee.
When done, print a one-line summary to stdout. Do not ask questions — run
autonomously to completion.
