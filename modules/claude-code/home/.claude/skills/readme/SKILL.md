---
name: readme
description: Create or update a project's root README.md, matching structure, sections and tone to the repo's audience — PRIVATE (personal, unpublished/unshared), PUBLIC (open source, anyone on the internet), or WORK (repo under a company/org, internal team audience). Use when the user asks to "write a README", "update the README", "generate a README for this repo/project", or wants root project documentation created or refreshed.
---

# readme

Writes or updates the root `README.md` of a project. The content and shape
of a good README depends entirely on who reads it, so this skill's first
job is figuring out the audience — **PRIVATE**, **PUBLIC**, or **WORK** —
and only then drafting sections, because a README written for the wrong
audience (OSS contributing boilerplate on a private script, or a bare
one-liner on a public library) is worse than none.

**Language:** the README is always written in **English**, regardless of
what language the conversation is in — same rule as generated commits and
PRs.

**Scope:** the root `README.md` only. Nested per-package READMEs in a
monorepo are out of scope unless the user asks for those too.

## Step 1 — Survey the repo

Before drafting anything, gather real facts — never invent install
commands, badges, contact info, or license text.

- Confirm this is a git repo and find its root (`git rev-parse
  --show-toplevel`). If there's no git repo at all, say so and ask whether
  to proceed anyway (README without version control is unusual but not
  invalid).
- Read the existing `README.md` if one exists — this run is an **update**,
  not a rewrite from nothing.
- Detect the project's tooling to learn its real name, description,
  install/run/test commands: `package.json`, `pyproject.toml`/`setup.cfg`,
  `Cargo.toml`, `go.mod`, `Gemfile`/`*.gemspec`, `composer.json`,
  `module.toml`, a `Makefile`, or equivalent. Pull install/usage/test
  commands from these (scripts, targets) rather than guessing generic ones.
- Detect what already exists: CI config (`.github/workflows/`,
  `.gitlab-ci.yml`, etc.), `LICENSE`/`LICENSE.md`, `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, a `docs/` directory, screenshots/assets, a
  `CODEOWNERS` file, Docker files.

## Step 2 — Determine the profile

Decide **PRIVATE**, **PUBLIC**, or **WORK** before drafting. Prefer
detection over asking, but don't guess past the point evidence runs out.

1. If the user has already stated the type outright ("this is a work
   repo", "det er et jobb-repo", "this is just for me"), use that — skip
   detection.
2. Otherwise, if `gh` is available and authenticated, check the real repo
   metadata: `gh api repos/{owner}/{repo} --jq '{ownerType: .owner.type,
   private: .private}'`. Map it:
   - `ownerType: User` + `private: true` → **PRIVATE**
   - `ownerType: User` + `private: false` → **PUBLIC**
   - `ownerType: Organization` + `private: true` → **WORK**
   - `ownerType: Organization` + `private: false` → ambiguous — could be a
     company's genuine open-source release, or an internal repo that
     happens to be public. Ask the user.
3. If there's no remote yet (local-only repo) or `gh` isn't available/
   authenticated, ask the user directly rather than guessing from
   ambiguous signals like folder location.
4. Don't persist the answer anywhere (no config file, no memory) — it's a
   fact about this repo the skill can re-derive next time, not a
   preference to remember.

## Step 3 — Pick sections for the profile

Use this table to decide what goes in. "Required" sections that can't be
filled with real facts (Step 1 found nothing) become an explicit, clearly
marked TODO for the user rather than invented content — say so out loud
when this happens.

| Section | PRIVATE | PUBLIC | WORK |
|---|---|---|---|
| Title + one-line description | required | required | required |
| Banner / logo | never | optional, only if real art exists | never |
| Badges | never | optional — only real, currently-true badges (CI, license, version); never decorative or placeholder ones | at most one CI badge |
| Table of contents | only if the file is genuinely long | once the README exceeds ~8 sections | once the README exceeds ~8 sections |
| Status (Active/WIP/Archived) | optional | optional | recommended |
| Screenshots / demo | never | recommended for anything with a UI | rare — only if it saves a teammate real time |
| Features / why it exists | never | recommended | rare — link to the product spec/ticket instead of restating it |
| Requirements / prerequisites | if non-obvious | required | required |
| Installation | if non-obvious | required, copy-paste commands that actually work | required, copy-paste commands |
| Usage / quick start | if non-obvious | required, real runnable examples | required |
| Configuration | if non-obvious | if applicable | if applicable — never real secret values, name the vars only |
| Architecture | never (a TODO/notes list is fine instead) | short, or link out to `docs/` | short, plus a link to ADRs/diagrams/wiki |
| Development & testing | brief notes to self are enough | "Contributing" section linking `CONTRIBUTING.md` | "Development" section: local setup + test/lint commands |
| Ownership / support | never | never | required — owning team, contact channel, on-call/escalation path, `CODEOWNERS` reference |
| Deployment / CI-CD | never | rare | recommended — pipeline and environment links |
| Roadmap | never | optional | rare — link to the ticket tracker instead |
| Contributing (OSS-style: PR policy, CoC) | never | required | never — internal PR process link only, no CoC boilerplate |
| Acknowledgments / credits | never | optional | never |
| License | omit, or one line ("Personal project, not licensed for reuse") | required — real SPDX identifier, last section | company-standard proprietary footer if one exists, otherwise omit — ask rather than invent legal text |

General rules that apply across all three:
- Lead with what the project *is* and *why it exists* in the first few
  lines — a reader (including future-you) should know that before
  scrolling, per the standard-readme/"Art of README" consensus this was
  designed against.
- No badge walls. A row of 8+ badges reads as noise, not signal, in 2026 —
  a small curated set beats a decorative row.
- Prefer linking to `docs/`, an internal wiki, or ADRs over inlining long
  detail — a README that tries to be the whole documentation site goes
  stale.
- No placeholder content ("TODO: describe project", lorem ipsum, fake
  badge URLs). Missing information is a named gap for the user to fill,
  not something to fabricate.

## Step 4 — Draft

- **New file:** write the full README using the sections chosen in Step 3,
  populated only with facts gathered in Step 1.
- **Existing file:** treat it as a base, not scratch paper — keep accurate
  existing prose and voice, add sections the profile requires that are
  missing, flag (to the user, in the plan below) any existing content that
  looks stale against what Step 1 found (e.g. install instructions that no
  longer match `package.json`), and don't restructure sections that are
  already correct just to match the table's order.
- Match tone to profile: PRIVATE is terse, first-person-friendly notes;
  PUBLIC is welcoming and scannable, plain professional voice by default
  (only lean into a more playful voice — heavier emoji, informal tone — if
  the project's existing README or the user clearly wants that); WORK is
  plain and factual, zero marketing language.

## Step 5 — Confirm, then write

- For an **update** to an existing README, or any **PUBLIC/WORK** README
  (visible to people beyond the user): show a short plan first — profile
  chosen and why, section list with what's added/removed/kept, and any
  gaps left as TODOs — and wait for approval before writing.
- For a brand-new **PRIVATE** README, drafting directly and showing the
  result is fine; no separate approval step needed.
- After writing, report back what changed in one or two sentences, not a
  restatement of the whole file.

## Boundaries

- Never fabricate badges, contact info, on-call links, license text, or
  metrics — omit or mark as a TODO instead.
- Never overwrite existing accurate content just to fit the section table.
- Don't turn the README into full documentation — link out once a section
  would run long.
- The profile table above is the default; if the user asks for a specific
  deviation for their project, follow the user over the table.
