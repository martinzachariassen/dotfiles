# Sections by profile

## Contents

- [The table](#the-table)
- [Rules for every profile](#rules-for-every-profile)
- [PUBLIC notes](#public-notes)
- [WORK notes](#work-notes)
- [PRIVATE notes](#private-notes)

## The table

| Section | PRIVATE | PUBLIC | WORK |
|---|---|---|---|
| Title + one-line description | required | required | required |
| Banner / logo | never | optional, only if real art exists | never |
| Badges | never | optional: only real, currently true ones (CI, licence, version, package downloads), at most ~5 | at most one CI badge |
| "Who is this for" / when not to use it | never | recommended, one or two lines | never |
| Table of contents | only if genuinely long | once past ~8 sections | once past ~8 sections |
| Status (Active / WIP / Maintenance / Archived) | optional | optional, required if unmaintained | recommended |
| Screenshots / demo | never | recommended for anything with a UI or rich CLI output | rare -- only if it saves a teammate real time |
| Features / why it exists | never | recommended | rare -- link the spec or ticket |
| Requirements / prerequisites | if non-obvious | required | required |
| Installation | if non-obvious | required, copy-paste commands that work | required, copy-paste commands |
| Quick start / usage | if non-obvious | required, real runnable examples, under 5 minutes to a first result | required |
| Configuration | if non-obvious | if applicable, a table of options | if applicable -- variable names only, never values |
| Architecture | never (a notes/TODO list is fine) | short, or link `docs/` | short, plus links to ADRs / diagrams / wiki |
| Development & testing | brief notes to self | under "Contributing", link `CONTRIBUTING.md` | "Development": local setup, test and lint commands |
| Deployment / CI-CD | never | rare | recommended: pipeline, environments, how to release |
| Operations | never | never | recommended: dashboards, runbook, alerts |
| Ownership / support | never | "Support" line: where to ask (Discussions, issues, `SUPPORT.md`) | required: owning team, channel, on-call / escalation, `CODEOWNERS` |
| Security | never | link `SECURITY.md` (how to report a vulnerability) | link the internal process if one exists |
| Roadmap | never | optional | rare -- link the tracker |
| Contributing (OSS: PR policy, Code of Conduct) | never | required | never -- link the internal PR process only |
| Acknowledgements | never | optional | never |
| Licence | omit, or one line ("Personal project, not licensed for reuse") | required: the real SPDX id, last section, linking `LICENSE` | the company's standard footer if there is one, otherwise omit. Ask rather than invent legal text |

## Rules for every profile

- **Lead with what and why.** By the end of the first screen a reader,
  future-you included, knows what this is and whether it is for them.
- **No badge walls.** A small set of true badges beats a decorative row.
- **Link, don't inline.** `docs/`, a wiki or ADRs hold the depth. A README
  that tries to be the whole documentation site goes stale first.
- **No placeholders.** No "TODO: describe project", lorem ipsum or example
  URLs. A gap is a named TODO you tell the user about.
- **Commands are copy-pasteable.** One command per line in fenced `sh`
  blocks, no `$ ` prompt prefix, and no machine-specific paths.
- **Headings are stable.** Other docs and issues link to `#installation`, so
  don't rename a heading without reason.

## PUBLIC notes

- Answer, in this order: what is it, why use it, how to install, how to get
  a first result, where to get help, how to contribute, the licence.
- GitHub renders these, so use them where they help a reader, not as
  decoration:
  - alerts for the one thing a reader must not miss: `> [!NOTE]`,
    `> [!IMPORTANT]`, `> [!WARNING]`
  - `<details><summary>...</summary>` to fold long optional material
  - Mermaid diagrams in a fenced `mermaid` block instead of image exports
  - `<picture>` with `prefers-color-scheme` sources for logos that must
    work on light and dark
- Every image gets real alt text, and no information exists only in an
  image.
- Badges come from the real source: the workflow file's badge URL on the
  default branch, shields.io for the licence and the registry version.
- Name the supported versions (runtime, OS) when they are a real
  constraint.

## WORK notes

- Readers are teammates and the on-call engineer at 3 a.m. The opening says
  what the service does and who owns it.
- **Ownership is required**: team name, chat channel, escalation or on-call
  rotation, and a pointer to `CODEOWNERS`. Missing facts become TODOs. Never
  invent a channel name.
- Link the operational surface: dashboards, runbook, alerts, environments,
  deploy pipeline.
- If the repo is internal-only, say so near the top ("Internal -- do not
  share outside <company>"), only if the user confirms the wording.
- Configuration names variables and where their values live (vault,
  parameter store), never the values.
- If relevant and known, note the data classification (handles PII,
  payment data).

## PRIVATE notes

- The reader is you in six months. Optimise for picking it back up: how to
  run it, what state it was left in, what bites.
- A "Notes" or "Gotchas" list beats prose. Keep it short and first-person.
- Skip everything aimed at strangers: badges, contributing, code of conduct,
  licence boilerplate.
