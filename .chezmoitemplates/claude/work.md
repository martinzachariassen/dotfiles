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

- **Secrets:** Azure Key Vault or GCP Secret Manager in deployed environments
  — never plain env files, never values in committed config. Local dev may use
  `.env` + Spring profiles with placeholders, but never carry real credentials
  into source.
- **Kubernetes:** `kubectx` / `kubens` for context + namespace switching (both
  installed via the work Brewfile); AKS auth via `kubelogin`. Don't paste
  cluster names, namespaces, or context details into commits, PR descriptions,
  or external tools.
- **Comms surfaces:** Microsoft Teams + Slack — but never paste internal
  message content into prompts, commits, or PRs.

## Confidentiality & attribution

The shared base's no-AI-attribution rule extends here to everything visible
internally — PR descriptions, design docs, code comments, Jira/Linear tickets,
chat. If a template tries to inject one, strip it. The same applies to
internal context: treat it as confidential, keep it in work repos only, and
never feed it to external tools or pastebins.
