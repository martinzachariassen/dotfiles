---
name: readme
description: Creates or updates a project's root README.md, shaping its sections and tone to who will read it -- PRIVATE (a personal repo nobody else reads), PUBLIC (open source, anyone on the internet) or WORK (a company or org repo read by teammates) -- and checks every command, link and badge against the repo before handing it back. Use when the user asks to "write a README", "update the README", "refresh the docs for this repo", "skriv en README", or wants root project documentation created or brought up to date.
argument-hint: "[private|public|work]"
allowed-tools: Bash(git status:*), Bash(git log:*), Bash(git rev-parse:*), Bash(git ls-files:*), Bash(git remote:*), Bash(gh repo view:*)
---

# readme

Writes or updates the root `README.md`. A good README depends on who reads it,
so the first job is the audience -- **PRIVATE**, **PUBLIC** or **WORK** -- and
only then the sections. A README written for the wrong audience (OSS
contributing boilerplate on a private script, a bare one-liner on a public
library) is worse than none.

**Language:** the README is **English**, whatever language the conversation
is in.

**Scope:** the root `README.md`. Nested package READMEs in a monorepo only if
the user asks.

**Arguments:** `$ARGUMENTS` -- `private`, `public` or `work` sets the profile
and skips detection.

## Workflow

Copy this checklist and tick it off as you go:

```
- [ ] 1. Survey the repo
- [ ] 2. Determine the profile
- [ ] 3. Pick the sections
- [ ] 4. Draft
- [ ] 5. Confirm, then write
- [ ] 6. Verify, fix, repeat
```

### 1. Survey the repo

Gather facts first. Never invent an install command, badge, contact or
licence.

- Repo root: `git rev-parse --show-toplevel`. No git repo: say so and ask
  whether to go on.
- An existing `README.md` makes this an **update**, not a rewrite.
- The project's real name, description and commands, from its tooling:
  `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`,
  `composer.json`, `Makefile`, `justfile`, `Taskfile.yml`, `Dockerfile`,
  `compose.yaml`. Commands come from scripts and targets that exist, never
  from what such a project "usually" runs.
- **Monorepo**: workspaces (`pnpm-workspace.yaml`, `"workspaces"`,
  `go.work`, a Cargo `[workspace]`) mean the root README is a map that links
  each package, not a merge of their docs.
- What already exists, so the README links instead of repeating:
  CI (`.github/workflows/`, `.gitlab-ci.yml`), `LICENSE`, `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`, `CODEOWNERS`, `docs/`,
  `CHANGELOG.md`, screenshots and other assets.
- The default branch, for any CI badge URL.

### 2. Determine the profile

Skip this if `$ARGUMENTS` or the user already named it ("this is a work
repo", "det er bare for meg").

Otherwise ask GitHub, which also returns the licence and description for
step 1:

```sh
gh repo view --json visibility,isInOrganization,owner,licenseInfo,description,repositoryTopics
```

| `isInOrganization` | `visibility` | Profile |
|---|---|---|
| false | PRIVATE | **PRIVATE** |
| false | PUBLIC | **PUBLIC** |
| true | PRIVATE / INTERNAL | **WORK** |
| true | PUBLIC | **ask** -- a company's open-source release, or an internal repo that happens to be public |

No remote, or `gh` missing or unauthenticated: **ask**. Never guess from the
folder path. Don't save the answer anywhere; it is re-derived each time.

### 3. Pick the sections

Use the profile table in [references/sections.md](references/sections.md).
A section the profile requires but step 1 found no facts for becomes a
clearly marked TODO, and you say so out loud. It is never filled with
invented content.

### 4. Draft

- **New file**: start from the profile's skeleton in
  [references/templates.md](references/templates.md), filled only with facts
  from step 1. The skeleton is a default, not a contract.
- **Existing file**: treat it as the base. Keep accurate prose and its voice.
  Add what the profile requires, flag content that step 1 shows is stale
  (install steps that no longer match `package.json`), and don't reshuffle
  correct sections just to match the table.
- **The first screen does the work.** Within the first ~10 lines a reader
  knows what this is, why it exists, and how to start.
- **Tone**:
  - PRIVATE: terse notes to future-you.
  - PUBLIC: welcoming, plain and professional. Go playful (emoji, a looser
    voice) only if the existing README or the user already does.
  - WORK: plain and factual, no marketing.

### 5. Confirm, then write

- An **update**, or any **PUBLIC** or **WORK** README (people other than the
  user will read it): first show a short plan. That is the profile and why,
  the sections added, kept or removed, any stale content found, and the
  TODOs left. Wait for approval.
- A **new PRIVATE** README: draft it directly and show the result.

### 6. Verify, fix, repeat

Check the written file against the repo, fix what fails, and check again
until it is clean:

- Every **relative link and image path** resolves to a file that exists
  (`git ls-files`).
- Every **command** maps to a real script, target or binary from step 1. Run
  the cheap, side-effect-free ones (`--help`, `--version`, `make -n
  <target>`), and never an install or anything that writes.
- Every **badge** points at a workflow file, licence or package that exists,
  on the right default branch.
- Every **TODO** is one you told the user about.
- No secret values, internal hostnames or personal data in a PUBLIC README.
- `markdownlint` or `markdownlint-cli2`, if installed, passes, or its
  remaining complaints are deliberate.

Then report what changed in one or two sentences, plus the TODOs left. Don't
restate the file.

## Boundaries

- Never fabricate badges, contacts, on-call links, licence text, metrics,
  benchmarks or testimonials. Leave them out, or mark them TODO.
- Never overwrite accurate existing content just to fit the table.
- The README is the front door, not the whole house. Once a section runs
  long, it moves to `docs/` and the README links to it.
- The profile table is the default. When the user asks for something
  different in their project, follow the user.
