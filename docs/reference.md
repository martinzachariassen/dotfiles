# Reference

- [Mapping](mapping.md) — every file in the repo and where it lands in `$HOME`, plus chezmoi internals.
- [Work setup](work-setup.md) — corporate Claude Code (`storecode`) install, separate from this repo.
- [`install.sh`](../install.sh) — the 6-phase wizard (fresh + existing Macs). `DRY_RUN=1` previews, `YES=1` accepts defaults.
- [`scripts/bootstrap-auth.sh`](../scripts/bootstrap-auth.sh) — post-install gh / az / gcloud / AKS / GKE / signing walkthrough. Idempotent.
- [`scripts/doctor.sh`](../scripts/doctor.sh) — read-only health check. Aliased as `chezdoctor`.
- [`Brewfile`](../Brewfile) — core, always installed. [`brewfiles/Brewfile.mac-apps`](../brewfiles/Brewfile.mac-apps) is the optional workstation feature. Profile-specific extras: [`brewfiles/Brewfile.personal`](../brewfiles/Brewfile.personal), [`brewfiles/Brewfile.work`](../brewfiles/Brewfile.work).
- [`examples/`](../examples/) — drop-in starter files for `direnv`, `pre-commit`, and Devbox project templates.
- [`raycast/`](../raycast/) — holding folder for encrypted Raycast `.rayconfig` exports. Ignored by chezmoi so it does not render into `$HOME`.
- [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) — shellcheck + chezmoi template-render + macOS brew-bundle check on every PR.
