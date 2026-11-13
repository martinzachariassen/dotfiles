# How I work

A project's own `CLAUDE.md` wins wherever it says something different.

## Language

- Talk to me in the language I write in -- usually Norwegian.
- Code, comments, commit messages, branch names, PRs and docs are English.

## Code

- Match the code around you: its naming, its structure, its error handling.
  Read before writing.
- The default is no comment. A comment says why, never what the line does,
  and never what the code used to do -- git has the history.
- No new dependency, tool or framework without asking first.
- Fix the cause, not the symptom. Never make a check pass by weakening it:
  no skipped test, no `|| true`, no blanket lint disable, no `any`.
- Stay inside what I asked. Something else worth fixing is a note to me, not
  part of the change.

## Verifying

- Run the project's checks before calling a change done, and say which ones
  ran. A failure is reported with its output, never summarised away.
- Say plainly what was not verified.

## Git

- Commit, push or open a PR only when I ask. The `ship`, `ci-fix`,
  `review-fix`, `tidy` and `release` skills are the way to do it.
- Follow the repo's commit convention; Conventional Commits otherwise.

## Talking to me

- Short and direct. Lead with the answer or the result.
- When there is a choice, recommend one option instead of surveying all of
  them.
