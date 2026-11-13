---
name: ship
description: Turns the working tree's uncommitted changes into a pushed branch and an open pull request -- branches off the default branch if needed, splits unrelated changes into separate commits that follow the repo's own commit convention, runs the project's checks, and opens (or updates) the PR with a filled-in body. Use when the user says "ship this", "open a PR", "commit and push", "make a pull request for these changes", "lag en PR", or otherwise wants the branch name, commit messages and PR written for them.
argument-hint: "[--draft] [base-branch]"
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git remote:*), Bash(git rev-parse:*), Bash(git symbolic-ref:*), Bash(gh repo view:*), Bash(gh pr view:*)
---

# ship

Takes what is in the working tree and turns it into a pull request a reviewer
can read cold: a well-named branch, commits split by concern, checks that ran,
and a PR body that says what changed, why, and how it was verified.

**Language:** everything shipped -- branch name, commits, PR title and body --
is **English**, whatever language the conversation is in. Talk to the user in
their language as usual.

**Arguments:** `$ARGUMENTS`
- `--draft` opens the PR as a draft.
- Any other word is the base branch to target instead of the default branch.

## Current state

- Status: !`git status --short --branch 2>&1 || true`
- Recent commits: !`git log --oneline -10 2>&1 || true`
- Diff size: !`git diff --stat HEAD 2>&1 | tail -5 || true`

## Workflow

Copy this checklist and tick it off as you go:

```
- [ ] 1. Survey the state
- [ ] 2. Learn the repo's rules
- [ ] 3. Safety scan
- [ ] 4. Branch
- [ ] 5. Group and commit
- [ ] 6. Run the checks
- [ ] 7. Decide where to push
- [ ] 8. Build the PR
- [ ] 9. Show the plan, wait for approval
- [ ] 10. Push and open the PR
```

### 1. Survey the state

- Read `git diff`, `git diff --staged` and the untracked files in full; the
  summary above is only a map.
- **Stop** if there is nothing to ship, if HEAD is detached, or if a rebase,
  merge or cherry-pick is in progress (`git status` says so). Explain what you
  found; never try to finish someone else's rebase.
- Find the default branch: `gh repo view --json defaultBranchRef --jq
  .defaultBranchRef.name`, falling back to `git symbolic-ref
  refs/remotes/origin/HEAD`.

### 2. Learn the repo's rules

The repo's own convention wins; Conventional Commits is the fallback, not the
override. Look, in this order, and stop at the first that states a rule:

1. The repo's `CLAUDE.md` / `AGENTS.md` (a commit or PR section).
2. `CONTRIBUTING.md` (root, `.github/` or `docs/`).
3. Tooling that enforces one: `commitlint.config.*`, `.commitlintrc*`,
   `.czrc`, a `commit-msg` hook in `lefthook.yml` / `.husky/` /
   `.pre-commit-config.yaml`.
4. `git log` on the default branch -- only if it is consistent.

Also note whether the repo requires **DCO sign-off** (`Signed-off-by:` in
recent commits, or CONTRIBUTING asks for it) -- then every commit uses
`git commit -s`.

Details, including the fallback rules and trailer order:
[references/commit-conventions.md](references/commit-conventions.md).

### 3. Safety scan

Before staging anything, scan the diff and the untracked files for:

- **Secrets**: `.env*` (other than `.env.example`), `*.pem`, `*.key`,
  `id_rsa*`, `*.p12`, credentials JSON, and lines that look like tokens
  (`AKIA...`, `ghp_...`, `github_pat_...`, `sk-...`, `xox[bp]-...`,
  `-----BEGIN ... PRIVATE KEY-----`, `password = "..."`).
- **Large or binary files** over ~1 MB that are not obviously meant to be
  tracked (and not already in Git LFS).
- **Generated or local-only files**: build output, `node_modules/`, `dist/`,
  `.DS_Store`, editor folders, coverage reports.

On any hit: **stop and ask**. Never commit a suspected secret, and never
"fix" it by silently leaving it out either -- say which file and why.

### 4. Branch

- On the default branch, or anything shared-looking (`main`, `master`,
  `develop`, `release/*`): create a branch named `<type>/<short-slug>`
  in kebab-case, describing the actual diff (`fix/statusline-width`, not
  `fix/changes`). Prefix the issue number if one is known
  (`fix/123-statusline-width`), and follow the repo's own branch pattern if
  step 2 found one.
- Already on a feature branch: stay on it.

### 5. Group and commit

- One concern, one commit. If the diff covers unrelated concerns, split it by
  staging per concern (`git add <paths>`, or `git add -p` for mixed files) --
  grouped by logical change, not one commit per file.
- Write each message with a HEREDOC so the body keeps its line breaks:

  ```sh
  git commit -F - <<'EOF'
  fix(ui): count what a hook reported

  Body explaining why.

  Co-Authored-By: ...
  EOF
  ```

- If a pre-commit hook fails, fix the cause and make a **new** commit. If a
  hook rewrote files (formatters), re-stage them and commit again.
- **Never** `--no-verify`, never `--amend` a commit that is already pushed.

### 6. Run the checks

Hand this step to the `check-runner` agent when it is available: it finds
and runs the command below in its own context and returns only the
failures. Otherwise find the one command the project treats as "is this green", in this order:

1. What `CLAUDE.md` / `CONTRIBUTING.md` says to run before committing.
2. A `Makefile` target `check`, then `test` (`make -n <target>` to confirm it exists).
3. `package.json` scripts `check`, `test`, `lint` (with the lockfile's
   package manager: `pnpm`, `yarn`, `bun` or `npm`).
4. `justfile`, `Taskfile.yml`, `cargo test`, `go test ./...`, `pytest`,
   `pre-commit run --all-files`.

Run it once. Then:

- **Green**: record the exact command in the test plan.
- **Red**: show the failing part of the output and ask: fix it, push anyway
  (the PR then says the checks fail and why), or abort. Never hide a red run.
- **Nothing found**, or it needs things this machine lacks (a database,
  credentials): say so in the test plan instead of inventing a command.

### 7. Decide where to push

- `gh repo view --json viewerPermission,isFork,parent` tells you whether you
  can push to this repo. Without write access, use the **fork workflow**:
  push to the user's fork (`gh repo fork --remote` if none exists, after
  asking) and open the PR against the upstream repo.
- `gh pr view --json url,state` on the branch: if an **open PR already
  exists**, this run pushes new commits to it and reports that PR; it does
  not open a second one, and it does not rewrite the existing body unless
  asked.

### 8. Build the PR

Look for a template, in this order: `.github/pull_request_template.md`,
`.github/PULL_REQUEST_TEMPLATE.md`, `.github/PULL_REQUEST_TEMPLATE/*.md`
(several: pick the one matching the change type; ask if it is genuinely
ambiguous), `docs/pull_request_template.md`, root
`pull_request_template.md`. Match case-insensitively.

- **A template exists: follow it exactly.** Every section it defines, in its
  order, with its headings, filled with real content. Do not add, drop,
  rename or reorder sections -- except where the template itself says an
  empty section may be dropped. Leave its checkboxes for the user to tick.
- **No template**: use the default in
  [references/pr-body.md](references/pr-body.md).

Either way, the title follows the same convention as the commits and
summarises the PR as a whole, and the attribution footer in context goes at
the very end.

### 9. Show the plan, wait for approval

Show, compactly:

- branch name, base branch, and whether it goes to a fork or opens a draft
- every commit: its message and its files
- the check command and its result
- which template was used, or that the default was
- the full PR title and body
- anything risky: CI or infra config, migrations, deleted files, dependency
  bumps, a red check run

Then **stop and wait for an explicit go-ahead**. Required every time, even
if an earlier run in this session was approved. Edits the user asks for
loop back to the relevant step.

### 10. Push and open the PR

```sh
git push -u origin <branch>
gh pr create --base <base> --title "<title>" --body-file - [--draft] <<'EOF'
<body>
EOF
```

- If `gh` is missing or not authenticated (`gh auth status`), or the remote
  is not on GitHub, say so and stop after the push -- give the user the
  title and body to paste. Do not work around it.
- Report the PR URL, and nothing else unless something went wrong.

## Boundaries

- Never force-push, never rewrite pushed history, never push to the default
  branch directly.
- Never `--no-verify`, and never commit a suspected secret.
- Never target a branch other than the default (or the one given in the
  arguments).
- Don't touch files the user didn't change -- no drive-by formatting.
- Don't add reviewers, assignees or labels unless asked.
- In a **public** repo, keep internal details out of the commits and the PR:
  internal hostnames, private ticket links, customer names, local paths.
