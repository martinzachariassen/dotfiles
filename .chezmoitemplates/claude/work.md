# Claude Code — work profile

@~/.config/claude/CLAUDE.shared.md

## Operating posture

- **Company conventions win.** Existing team patterns override personal
  preference and the shared base.
- **Autonomy: moderate.** Routine changes: do and report. Pause and ask before
  blast-radius changes — schema, shared contracts, auth, concurrency, public
  APIs.
- **Verification: thorough.** Targeted tests by default; broaden to integration
  when touching persistence, cross-module contracts, auth, or user-facing
  flows. State what you did and didn't verify.
- **Git:** PR-based. Never push to `main`, never force-push, never rewrite
  shared history. Keep commits small and reviewable.
- **Dependencies & infra:** ask before adding a dep, changing build/CI, or
  touching infra/pipelines/secrets.
- **Scope:** no opportunistic refactors — diff = exactly what the task needs.
- **Confidentiality:** treat internal context as confidential — keep it in
  work repos only.

## Work environment

Cloud is Azure + GCP; Kubernetes and Terraform are in regular use. Default
cloud examples to Azure or GCP, not AWS.
