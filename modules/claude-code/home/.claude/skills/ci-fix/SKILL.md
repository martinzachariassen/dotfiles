---
name: ci-fix
description: Finds out why CI is red on the current branch or pull request and fixes it -- reads the failed GitHub Actions logs, reproduces the failing step locally, makes the smallest fix that turns it green, and commits it to the same branch. Stops instead of guessing when the failure is not in the code (secrets, permissions, a flaky runner, the network). Use when the user says "CI is failing", "fix the build", "the checks are red", "why did the pipeline fail", "fiks CI", or points at a failed run or PR.
argument-hint: "[pr-number | run-id | run-url]"
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh run list:*), Bash(gh run view:*), Bash(gh repo view:*)
---

# ci-fix

Turns a red CI run into a green one with the smallest honest change. The job
is to find the **cause**, not to make the check stop complaining.

**Language:** commits are **English**, whatever language the conversation is
in.

**Arguments:** `$ARGUMENTS` -- a PR number, a run id or a run URL. Empty: the
PR for the current branch, or else the latest run on it.

## Current state

- Branch: !`git branch --show-current 2>&1 || true`
- Status: !`git status --short 2>&1 | head -20 || true`

## Workflow

Copy this checklist and tick it off as you go:

```
- [ ] 1. Find the failing run
- [ ] 2. Read the failure
- [ ] 3. Classify it
- [ ] 4. Reproduce locally
- [ ] 5. Fix the cause
- [ ] 6. Verify, then commit
- [ ] 7. Show, wait for approval, push
```

### 1. Find the failing run

- `gh` missing or not authenticated (`gh auth status`): say so and stop. Not
  GitHub Actions (GitLab CI, Jenkins, CircleCI): ask the user to paste the
  failing log and continue from step 3.
- A PR: `gh pr checks <pr>` lists the checks and their run links.
- Otherwise: `gh run list --branch <branch> --limit 5`, and take the newest
  failed run **for the current HEAD** (`headSha`). A failure on an older
  commit may already be fixed -- say so rather than chase it.
- Uncommitted changes in the working tree: stop and ask first. A fix on top
  of unrelated work becomes one tangled commit.

### 2. Read the failure

- `gh run view <id> --log-failed` -- only the failed steps. If that is
  empty or truncated, `gh run view <id> --json jobs` to find the job, then
  `gh run view --job <job-id> --log`.
- Find the **first** error, not the last. Later errors are usually fallout.
- Open the workflow file under `.github/workflows/` for the failing job: what
  command it runs, on which OS and runtime version, with which env.

### 3. Classify it

| Kind | Signs | Action |
|---|---|---|
| **Code** | a test, type check, lint or build fails on our change | fix it (step 4) |
| **Environment drift** | passes locally, fails in CI; runtime/OS/tool version differs, a new upstream release | fix the pin or the code, and say which |
| **Flaky** | same commit has passed before, timeouts, races, network fetches | **don't** change code; offer `gh run rerun <id> --failed` and name the flaky test |
| **Infra / secrets** | `401`/`403`, missing secret, permission denied on `GITHUB_TOKEN`, quota, runner offline | **stop**: explain what is missing and who can fix it |
| **Workflow file** | YAML error, a removed action version, a wrong path | fix the workflow, and flag it as a CI change in the plan |

When it is not clearly **Code**, show the classification and the evidence
before touching anything.

### 4. Reproduce locally

Run the **same** command the failing step runs, from the workflow file, with
the same relevant env (`CI=true`, the matrix values that matter). Prefer the
narrowest form: one test file, one package, one lint target.

- Fails locally too: good, you have a loop.
- Passes locally: compare versions (runtime, lockfile, OS). The difference
  is the lead. Don't commit a guess you cannot verify -- say it is
  unverified in the plan.

### 5. Fix the cause

- The smallest change that makes the failing step correct. One concern.
- **Never** make it green by weakening the check: no skipping or deleting a
  test, no `|| true`, no `continue-on-error`, no lowering a coverage
  threshold, no blanket lint disable, no loosening a type to `any`. If the
  check itself is wrong, say so and ask.
- A test that now expects different output: only update it if the new
  behaviour is the intended one, and say why.

### 6. Verify, then commit

- Rerun the reproduction from step 4 until it passes, then the project's
  full check command (as `ship` would find it), so the fix breaks nothing
  else. Run that full check through the `check-runner` agent when it is
  available, so only its failures come back.
- Commit to the **same branch**, following the repo's commit convention
  (same rules as the `ship` skill: repo convention first, Conventional
  Commits as the fallback, `git commit -s` if the repo uses DCO). The body
  names the failing check and the cause.

### 7. Show, wait for approval, push

Show: the failing run and step, the cause and its kind, the diff, the
commands that now pass. Then **stop and wait for an explicit go-ahead** --
every time. After it: `git push`, and watch the new run with
`gh run watch <new-id> --exit-status` if the user wants to wait for it.
Report the result in one line.

## Boundaries

- Never force-push, never rewrite pushed history, never push to the default
  branch.
- Never `--no-verify`, and never rerun a failing job in a loop hoping it
  goes green.
- Never touch secrets, repository settings or branch protection.
- Never change a workflow file to dodge a failure -- only to fix one, and
  always flagged in the plan.
- If several unrelated checks fail, fix them as separate commits, or ask
  which one matters first.
