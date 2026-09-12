---
name: ship
description: Take the current uncommitted changes, branch off if needed, commit them (split into logical commits when they cover unrelated concerns), push, and open a pull request. Use when the user asks to "ship this", "open a PR for these changes", or otherwise wants branch name + commit message(s) + PR generated for them instead of writing it by hand.
---

# ship

Turns the working tree's current changes into a pushed branch and an open
pull request, writing the branch name, commit message(s), and PR title/body
so the user doesn't have to.

**Language:** every piece of generated content — branch name, commit
subjects/bodies, PR title, and PR body (including any prose filled into a
detected template) — is written in **English**, regardless of what language
the conversation with the user is in. Talk to the user in their language as
usual; only the shipped artifacts themselves are English.

## Steps

1. **Survey the state.**
   - `git status` and `git diff` / `git diff --staged` to see what changed.
   - If there are no changes at all (staged, unstaged, or untracked), say so and stop.
   - `git log --oneline -20` to sanity-check the repo isn't doing something
     actively incompatible (e.g. a strict non-Conventional-Commits linter
     config); otherwise this doesn't change the convention used below.
   - Note the current branch and the repo's default branch (`git symbolic-ref
     refs/remotes/origin/HEAD` or `gh repo view --json defaultBranchRef`).

2. **Branch.**
   - If the current branch *is* the default branch (main/master) or another
     shared/protected-looking branch, create and check out a new branch.
     Name it kebab-case, prefixed with the Conventional Commits type that
     matches the change (`feat/`, `fix/`, `chore/`, `refactor/`, `docs/`,
     `test/`, `perf/`, `ci/`, `build/`) — short and descriptive of the
     actual diff, not generic ("ship-changes").
   - If already on a feature branch (not default), stay on it — don't create
     a nested branch.

3. **Group and commit.**
   - Look at the diff as a whole. If everything belongs to one concern, stage
     everything and make one commit.
   - If the changes clearly cover more than one unrelated concern (e.g. an
     unrelated drive-by fix alongside a feature, or changes to clearly
     separate areas of the codebase), split into multiple commits by staging
     hunks/files per concern (`git add <files>` per group, or `git add -p`
     for mixed files) — group by logical change, not mechanically one commit
     per file.
   - Always write commits as **Conventional Commits**
     (`type(scope): subject`), regardless of what the repo's existing
     history does — this is a fixed rule for this skill, not something to
     infer from `git log`:
     - `type` is one of `feat`, `fix`, `chore`, `refactor`, `docs`, `test`,
       `perf`, `ci`, `build`, `style`; `scope` is optional and only added
       when it's genuinely clarifying (a package/module/dir name).
     - `subject`: imperative mood ("add", not "added"/"adds"), lowercase,
       no trailing period, ideally ≤50 chars, hard cap ~72.
     - Body (when the change needs explaining beyond the subject): wrap at
       ~72 chars, explain *why*, not a restatement of the diff; separated
       from the subject by a blank line.
     - Use a `BREAKING CHANGE:` footer (or `!` after the type/scope) for any
       breaking change.
     - One logical change per commit — this is also *why* step 3 splits
       unrelated concerns instead of bundling them.
   - Apply the standard attribution trailer used in this environment (see
     the git commit instructions already in context) as its own
     trailer line, after any `BREAKING CHANGE:` footer.

4. **Check for a PR template first.**
   - Look for, in this order: `.github/PULL_REQUEST_TEMPLATE.md`,
     `.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE/*.md`
     (multiple templates — pick the one whose filename best matches the
     change type, e.g. `feature.md` vs `bugfix.md`; ask the user if it's
     genuinely ambiguous), `docs/PULL_REQUEST_TEMPLATE.md`, and a root-level
     `PULL_REQUEST_TEMPLATE.md`.
   - **If a template exists, follow it slavishly.** Fill in every section
     it defines, in its own order, with real content — don't rename,
     reorder, drop, or add sections, don't paraphrase its headings into
     "Summary"/"Test plan" if it uses different ones, and leave any of its
     checkboxes for the user to tick rather than pre-checking them
     yourself. The only thing added on top is the standard attribution
     footer already in context, appended at the very end after the
     template's own content.
   - **If no template exists anywhere in the repo, apply these PR best
     practices** (this is the fixed default for this skill, not something
     to reinvent per repo):
     1. **Title** in Conventional Commits format (`type(scope): summary`,
        same rules as commit subjects) — summarizes the PR as a whole, not
        just the first commit if there are several.
     2. **One concern per PR.** If step 3 already had to split into
        unrelated commits, say so plainly here too and suggest separate
        PRs rather than bundling — don't paper over it with a long body.
     3. **`## Summary`** — 1-3 bullets on *what* changed and *why*, written
        for a reviewer with no prior context, not a restatement of the diff.
     4. **`## Test plan`** — a checklist of how this was or should be
        verified (commands run, tests added/passing, manual steps) — not
        a vague "tested locally".
     5. **Link related work** — `Closes #N` / `Fixes #N` when an issue is
        known; otherwise omit rather than guessing.
     6. **Call out risk explicitly** — breaking changes, migrations, config
        or infra changes, anything needing a careful review pass — as its
        own short line or section, not buried in the summary.
     7. **Screenshots/output** for anything user-visible or CLI-output-visible,
        described as a placeholder the user can fill in if you can't
        generate one (e.g. no way to render UI here).
     8. Kept factual and scannable — no filler, no marketing language, no
        restating the title in prose.
     - End with the standard PR footer already in context.

5. **Show the plan and stop for approval.**
   - Show the user: branch name, the list of commits made (message + files
     in each), which PR template was found (if any) or that best-practice
     defaults are being used, and the full PR title/body you intend to use.
   - Wait for explicit go-ahead before continuing. This confirmation step is
     required every time — do not skip it even if a previous invocation was
     approved.

6. **Push and open the PR.**
   - `git push -u origin <branch>`.
   - `gh pr create --title "..." --body "..."` targeting the repo's default
     branch, using the body built in step 4.
   - If `gh` isn't authenticated or the repo has no GitHub remote, say so
     explicitly instead of trying to work around it.
   - Report the PR URL back to the user.

## Boundaries

- Branch name, commits, and PR title/body are always in English, even in a
  conversation conducted in another language — see Language above.
- Never force-push, never rewrite history that's already pushed, never
  target a branch other than the repo's actual default branch without being
  asked.
- Don't restage or touch files the user didn't change (no unrelated
  formatting/cleanup commits).
- If the diff is trivial to describe but touches something risky (migrations,
  CI config, deleted files), call that out in the plan shown at step 5 rather
  than silently proceeding.
