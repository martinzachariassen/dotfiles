---
name: tidy
description: Cleans up a local git repo after a pull request is merged -- switches to the default branch, pulls it, prunes deleted remote branches, and deletes local branches whose work is already in the default branch (including squash- and rebase-merged ones, checked through the PR state), never one with unmerged or unpushed work. Use when the user says "tidy up", "clean up branches", "the PR is merged", "back to main", "rydd opp", or wants stale local branches removed.
argument-hint: "[--dry-run]"
allowed-tools: Bash(git status:*), Bash(git branch:*), Bash(git log:*), Bash(git rev-parse:*), Bash(git symbolic-ref:*), Bash(git worktree list:*), Bash(git stash list:*), Bash(git cherry:*), Bash(gh repo view:*), Bash(gh pr list:*), Bash(gh pr view:*)
---

# tidy

Brings a repo back to a clean starting point after a merge: on the default
branch, up to date, with no local branches left over from work that has
landed. It deletes **only** what it can prove is merged.

**Arguments:** `$ARGUMENTS` -- `--dry-run` shows the plan and stops.

## Current state

- Branch: !`git branch --show-current 2>&1 || true`
- Status: !`git status --short 2>&1 | head -20 || true`
- Local branches: !`git branch -vv 2>&1 | head -40 || true`

## Workflow

```
- [ ] 1. Check it is safe to switch
- [ ] 2. Update the default branch
- [ ] 3. Sort the local branches
- [ ] 4. Show the plan, wait for approval
- [ ] 5. Delete, then report
```

### 1. Check it is safe to switch

- Find the default branch: `gh repo view --json defaultBranchRef --jq
  .defaultBranchRef.name`, falling back to `git symbolic-ref --short
  refs/remotes/origin/HEAD`.
- **Stop** if the working tree has uncommitted changes, or a rebase, merge
  or cherry-pick is in progress. Say what is there; never stash or discard
  it for the user.

### 2. Update the default branch

```sh
git switch <default>
git pull --ff-only --prune
```

`--ff-only` fails rather than create a merge commit. If it fails, the local
default branch has commits that are not on the remote: stop and show them
(`git log origin/<default>..<default>`). Never reset it.

### 3. Sort the local branches

For every local branch other than the default, put it in exactly one bucket:

| Bucket | How you know | Action |
|---|---|---|
| **Merged** | `git branch --merged <default>` lists it | delete with `git branch -d` |
| **Squash/rebase-merged** | `gh pr list --head <branch> --state merged` finds a merged PR, **and** the branch has no commits after that PR's head (`gh pr view <n> --json headRefOid` equals the branch tip) | delete with `git branch -D`, citing the PR |
| **Remote gone, no PR proof** | `git branch -vv` shows `[origin/...: gone]` but no merged PR matches | **keep**, list it and ask |
| **Unpushed or open** | commits not on any remote, or an open PR | **keep** |

Never touch:

- the default branch, `main`, `master`, `develop`, `release/*`
- a branch checked out in another worktree (`git worktree list`)
- a branch with commits after its merged PR's head -- that is new work

No `gh` (missing, unauthenticated, not GitHub): only the **Merged** bucket
can be proven. Everything else is kept and listed.

Also mention, without acting: stashes (`git stash list`) and worktrees whose
branch is merged. They are the user's to drop.

### 4. Show the plan, wait for approval

One compact list: what will be deleted and the proof for each (merged into
`<default>`, or `PR #n merged`), and what is kept and why. `--dry-run`, or
nothing to delete: stop here.

Otherwise **wait for an explicit go-ahead**. Deleting a branch is local, but
its commits become hard to find afterwards.

### 5. Delete, then report

Delete exactly the approved list. Print each deleted branch with its tip SHA
(`git branch -d` prints it), so it can be restored with `git branch <name>
<sha>`. Then report in one or two lines: on `<default>` at `<sha>`, N
branches deleted, M kept.

## Boundaries

- Never delete a remote branch. GitHub's "delete branch on merge" or the
  user does that.
- Never `git reset`, `git clean`, `git stash` or `git checkout -- .` --
  nothing here may lose uncommitted work.
- Never `-D` a branch without a merged PR that proves it.
