# Claude Code — work profile

@~/.config/claude/CLAUDE.shared.md

The **work** profile (chezmoi `profile = work`). The shared base above holds who
I am and how I code; the rest of this file is how Claude Code should operate on
work machines.

## Operating posture

- **Company conventions win.** Existing team patterns and standards override
  personal preference and the shared base's defaults.
- **Autonomy: moderate.** Make routine changes and report, but pause and ask
  before anything with blast radius — schema changes, shared contracts, auth,
  concurrency, public APIs.
- **Verification: thorough.** Run targeted tests, and broaden to integration
  checks when the change touches persistence, cross-module contracts, auth, or
  user-facing workflows. State exactly what you did and didn't verify.
- **Git:** PR-based workflow. Never push to `main`, never force-push, never
  rewrite shared history. Keep commits small and reviewable.
- **Dependencies & infra:** ask before adding a dependency, changing build/CI
  config, or touching infrastructure, pipelines, or secrets.
- **Scope:** no opportunistic refactors — keep the diff to exactly what the
  task needs so review stays cheap.
- **Confidentiality:** treat anything internal as confidential — keep it in
  work repos, never in the shared base or a personal-profile file.

## Work environment

Cloud is Azure + GCP; Kubernetes and Terraform are in regular use. Default
cloud examples to Azure or GCP, not AWS.
