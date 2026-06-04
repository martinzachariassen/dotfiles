# Reference

- [Mapping](mapping.md) — every file in the repo and where it lands in `$HOME`, plus chezmoi internals.
- [`install.sh`](../install.sh) — the 5-step setup wizard for fresh and existing Macs. `DRY_RUN=1` previews, `YES=1` accepts defaults.
- [`scripts/bootstrap-auth.sh`](../scripts/bootstrap-auth.sh) — post-install 1Password, gh, optional cloud auth, and signing walkthrough. Idempotent.
- [`scripts/doctor.sh`](../scripts/doctor.sh) — read-only health check. Aliased as `chezdoctor`.
- [`Brewfile`](../Brewfile) — core, always installed. [`brewfiles/Brewfile.mac-apps`](../brewfiles/Brewfile.mac-apps) is the optional workstation apps module (GUI apps + AI tooling), gated by the `macApps` feature. Profile-specific extras: [`brewfiles/Brewfile.personal`](../brewfiles/Brewfile.personal), [`brewfiles/Brewfile.work`](../brewfiles/Brewfile.work).
- [`examples/`](../examples/) — drop-in starter files for `pre-commit` and mise project templates (`mise.toml`).
- [`raycast/`](../raycast/) — holding folder for encrypted Raycast `.rayconfig` exports. Ignored by chezmoi so it does not render into `$HOME`.
- [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) — shell parser checks, error-level ShellCheck, chezmoi template-render, and macOS brew checks on every PR.
- [`AGENTS.md`](../AGENTS.md) — repo-local brief for AI agents (Claude Code, Codex, Copilot) editing this repo. Source of truth; the bridges below all point at it. See [AI tools](ai-tools.md) for the full layering.
- [`CLAUDE.md`](../CLAUDE.md) — one-line bridge (`@AGENTS.md`) so Claude Code picks up `AGENTS.md` (it only auto-loads `CLAUDE.md`).
- [`.github/copilot-instructions.md`](../.github/copilot-instructions.md) — Copilot bridge to `AGENTS.md`.
