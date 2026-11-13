# Default PR body

Use this only when the repo has no pull request template.

## Rules

- **Title**: same convention as the commits, summarising the whole PR -- not
  just the first commit.
- **One concern per PR.** If step 5 had to split unrelated commits, say so in
  the plan and suggest separate PRs instead of papering over it here.
- Written for a reviewer with no context: what changed, why, how it was
  verified, what could go wrong. Scannable, factual, no filler, no marketing,
  no restating the title as a sentence.
- Drop a section that has nothing to say, rather than writing "N/A".
- Only link issues you actually know about. Never guess a number.

## Sections

```markdown
## Summary

- <what changed and why, 1-3 bullets>

## Test plan

- [x] `<exact command that ran>` -- passes
- [ ] <manual step for the reviewer, if any>

## Risk

<breaking change, migration, config/infra change, rollback path -- or drop it>

## Screenshots

<only for user-visible or CLI-visible output; a placeholder the user fills in
if you cannot produce one>

Closes #<n>
```

`Closes #n` / `Fixes #n` goes on its own line at the end, so GitHub links and
closes the issue on merge.

## Example

```markdown
## Summary

- Measure the status line after the model name is filled in, so long model
  names no longer push the git branch off the line.
- Add a test with a 40-character model name.

## Test plan

- [x] `make check` -- passes
- [ ] Open Claude Code in a repo on a long branch and check the line by eye

Closes #42
```
