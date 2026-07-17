# Repository instructions for GitHub Copilot

The full contributor rulebook for this repo lives in [`../CLAUDE.md`](../CLAUDE.md)
— read it before proposing changes. It's the single source of truth; this file
mirrors only the non-negotiables so Copilot has them inline:

- Edit chezmoi sources under `src/`, never the rendered copies in `$HOME`.
- Open a PR; never push directly to `main`.
- Conventional Commits for every commit and PR title (subject ≤ 72 chars).
- Never commit secrets — use placeholders or a secret-manager reference.

See [`../CLAUDE.md`](../CLAUDE.md) for the `src/` split, chezmoi conventions,
quality gates, and the edit → apply loop.
