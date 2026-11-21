# Commit conventions

## Following the repo's own convention

When step 2 of the workflow finds a rule, it wins over everything below.
Typical shapes and what they mean:

| Found | Do |
|---|---|
| commitlint with `@commitlint/config-conventional` | Conventional Commits, plus whatever `rules` the config adds (allowed scopes, max length, case) |
| `.czrc` / commitizen | Conventional Commits, unless its adapter says otherwise |
| CONTRIBUTING describes a format ("`area: summary`", Gitmoji, a ticket prefix like `ABC-123:`) | that format, exactly |
| A consistent `git log` with no written rule | match it: casing, prefix style, tense |
| A mixed or messy log, no written rule | the fallback below |

If a `commit-msg` hook rejects a message, read its error, rewrite the message
to satisfy it, and commit again. Never bypass it.

## Fallback: Conventional Commits

```
<type>(<scope>)!: <subject>

<body>

<footers>
```

- **type**: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `build`,
  `ci`, `chore`, `style`, `revert`.
- **scope**: optional. Add one only when it clarifies -- a package, module or
  top-level directory. Reuse scopes already in the log.
- **subject**: imperative ("add", not "added"/"adds"), lowercase, no trailing
  period, aim for 50 characters, hard limit 72.
- **body**: wrapped at 72, separated by a blank line. It says **why** -- the
  problem, the constraint, the trade-off -- not a restatement of the diff.
  Leave it out when the subject is the whole story.
- **breaking change**: `!` after the type/scope, plus a
  `BREAKING CHANGE: <what breaks and how to migrate>` footer.

## Footers and trailers

In this order, each on its own line, after one blank line:

1. `BREAKING CHANGE: ...`
2. Issue references the repo uses in commits (`Refs: #123`), if any.
3. `Signed-off-by: Name <email>` -- added by `git commit -s` when the repo
   requires DCO. Never type it by hand with a different identity.
4. The attribution trailer given in context, last.

## Examples

```
fix(statusline): stop truncating the branch at 20 columns

The width was computed before the model name was known, so long model
names pushed the branch off the line. Measure after both are filled in.
```

```
feat(api)!: return ISO 8601 timestamps

BREAKING CHANGE: `created_at` is now a string like "2026-01-31T12:00:00Z"
instead of a Unix epoch integer. Clients parsing it as a number must
switch to a date parser.
```
