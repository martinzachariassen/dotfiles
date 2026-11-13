---
name: review-fix
description: Works through the review feedback on a pull request -- fetches the unresolved review threads and review comments, decides for each whether to change the code, answer it or push back, makes the changes as commits on the same branch, and after approval pushes, replies in each thread and resolves the ones the change settles. Use when the user says "address the review", "fix the review comments", "reviewer asked for changes", "fiks review-kommentarene", or points at a PR with requested changes.
argument-hint: "[pr-number | pr-url]"
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh repo view:*)
---

# review-fix

Turns a reviewer's comments into either a change or an answer, one thread at
a time, so the reviewer can re-review by reading the replies rather than
re-reading the whole diff.

**Language:** commits are **English**. Replies on the PR are in the language
the reviewer wrote in. Talk to the user in their language as usual.

**Arguments:** `$ARGUMENTS` -- a PR number or URL. Empty: the PR for the
current branch.

## Current state

- Branch: !`git branch --show-current 2>&1 || true`
- Status: !`git status --short 2>&1 | head -20 || true`
- PR: !`gh pr view --json number,title,reviewDecision,url 2>&1 || true`

## Workflow

Copy this checklist and tick it off as you go:

```
- [ ] 1. Find the PR and check out its branch
- [ ] 2. Collect the feedback
- [ ] 3. Triage every item
- [ ] 4. Make the changes
- [ ] 5. Verify, then commit
- [ ] 6. Show the plan, wait for approval
- [ ] 7. Push, reply, resolve
```

### 1. Find the PR and check out its branch

- `gh` missing or not authenticated (`gh auth status`): say so and stop.
- The current branch must be the PR's head branch
  (`gh pr view <pr> --json headRefName`). If it is not, ask before
  `gh pr checkout <pr>`.
- Uncommitted changes in the working tree: stop and ask first. Review fixes
  on top of unrelated work become one tangled commit.
- Behind the remote (`git status` says so): `git pull --ff-only` first, or
  the fixes land on a stale tree. A pull that cannot fast-forward: stop.

### 2. Collect the feedback

Three places hold it; read all three.

- **Inline threads**, with their resolved state -- only GraphQL has it:

  ```sh
  gh api graphql -F owner='{owner}' -F repo='{repo}' -F n=<pr> -f query='
    query($owner:String!,$repo:String!,$n:Int!){
      repository(owner:$owner,name:$repo){ pullRequest(number:$n){
        reviewThreads(first:100){ nodes{
          id isResolved isOutdated path line
          comments(first:50){ nodes{ databaseId author{login} body url } }
        } } } } }'
  ```

  Skip threads with `isResolved: true`. An `isOutdated` thread still counts
  -- the line moved, the point may not have.
- **Review bodies**: `gh pr view <pr> --json reviews` -- the summary a
  reviewer wrote when submitting, often the most important request.
- **Conversation comments**: `gh pr view <pr> --json comments`.

Ignore bots that only report status (CI, coverage, deploy previews) unless
they name a concrete problem. Read the whole thread, not just its first
comment: a later reply may have narrowed or withdrawn the request.

### 3. Triage every item

Read the code each comment points at (`path`, `line`, and enough around it),
then put every item in exactly one bucket:

| Bucket | When | Action |
|---|---|---|
| **Change** | the reviewer is right, or it is a harmless preference | change the code |
| **Answer** | a question, or a misreading the code already handles | reply only, with the reason or the line that answers it |
| **Push back** | the change would be wrong, or out of scope for this PR | reply with why; offer a follow-up issue for scope |
| **Ask the user** | a design call, a product decision, or the reviewer and the code's author would plausibly both be right | stop on it and ask |

Never put an item in **Change** only because a reviewer asked. A suggestion
that would introduce a bug is **Push back**, with the reason.

### 4. Make the changes

- One commit per concern, not one per comment and not one for everything.
  Comments asking for the same thing share a commit.
- Follow the repo's commit convention (same rules as the `ship` skill: repo
  convention first, Conventional Commits as the fallback, `git commit -s` if
  the repo uses DCO). The subject says what changed, not "address review".
- Stay inside what was asked. A fix you notice on the way is a separate,
  clearly labelled commit, or a note to the user.
- A `suggestion` block from the reviewer: apply it as written unless it is
  wrong, then it is **Push back**.

### 5. Verify, then commit

Run the project's checks (as `ship` would find them) through the
`check-runner` agent when it is available, so only its failures come back.
A failure your change caused gets fixed before going on; one that was
already red is named in the plan, not hidden.

### 6. Show the plan, wait for approval

Show, per item: the reviewer, the file and line, the bucket, and either the
commit that settles it or the reply you will post -- every reply drafted in
full. Then the commits, and the checks that ran. **Stop and wait for an
explicit go-ahead** -- every time. The user may edit replies or move items
between buckets.

### 7. Push, reply, resolve

After approval, in this order:

1. `git push`.
2. Reply in each inline thread to its first comment's `databaseId`:
   `gh api repos/{owner}/{repo}/pulls/<pr>/comments/<id>/replies -f body=...`.
   A **Change** reply names the commit (short SHA) that settled it.
3. Resolve only the **Change** threads whose fix is pushed:
   `gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:"<id>"}){thread{isResolved}}}'`.
   **Answer** and **Push back** threads stay open -- the reviewer decides
   whether the answer settles them.
4. Review-body and conversation items: one `gh pr comment <pr>` that answers
   them together, not one comment each.

Do not re-request review unless the user asks. Report in one line: commits
pushed, threads replied to, threads resolved, items left open.

## Boundaries

- Never force-push, never rewrite pushed history, never push to the default
  branch.
- Never dismiss a review, approve, or merge.
- Never resolve a thread you only replied to, and never one someone else
  opened a question in after your fix.
- Never post anything before the approval in step 6.
