# Default PR body

Use this only when the repo has no pull request template.

## Rules

- **Title**: same convention as the commits, summarising the whole PR -- not
  just the first commit.
- **One concern per PR.** If step 5 had to split unrelated commits, say so in
  the plan and suggest separate PRs instead of papering over it here.
- **Lead with why.** The first sentence says what problem this solves or what
  changes for whoever uses the code; the bullets after it say how. A reviewer
  who reads only that sentence should know whether the PR matters to them.
- Written for a reviewer with no context: what changed, why, how it was
  verified, what could go wrong. Scannable, factual, no filler, no marketing,
  no restating the title as a sentence.
- Name files, functions and commands in backticks. Do not list the changed
  files -- the diff does that.
- Summary and Testing are always there. Drop any other section that has
  nothing to say, rather than writing "N/A".
- **Never leave a placeholder in the body.** Anything only the user can supply,
  such as a screenshot, is raised in the step 9 plan, not left in the PR.
- Only link issues you actually know about. Never guess a number.

## Sections

```markdown
## Summary

<one or two sentences: the problem, and what changes for whoever uses this>

- <what changed, 1-4 bullets, most important first>

## Testing

<what ran and its result, as a sentence: "`make check` passes.">

- [ ] <manual step for the reviewer, if any>

## Review notes

<optional: where to start reading, a deliberate choice that may look wrong,
what was left out on purpose>

## Risk

<optional: breaking change, migration, config or infra change -- and how to
roll it back>

## Output

<optional: for CLI-visible changes, a real run inside <details>; for UI
changes, a screenshot>

Closes #<n>
```

`Closes #n` / `Fixes #n` goes on its own line at the end, so GitHub links and
closes the issue on merge. Leave it out when there is no known issue.

## Example

```markdown
## Summary

Long model names pushed the git branch off the end of the status line, so the
branch was invisible exactly when it mattered most.

- Measure the line after the model name is filled in, not before.
- Add a test with a 40-character model name.

## Testing

`make check` passes, including the new test.

- [ ] Open Claude Code in a repo on a long branch and check the line by eye

## Review notes

The width calculation in `statusline.sh` is the only real change; the rest is
the test.

Closes #42
```
