# AI tools

## Repo-local instructions

[`AGENTS.md`](../AGENTS.md) contains instructions for AI agents working in this
dotfiles repo. It is intentionally repo-local metadata and is ignored by
chezmoi, so it is not installed into `$HOME`.

The file covers the parts agents most often get wrong here: chezmoi source
mapping, avoiding direct edits to rendered `$HOME` files, keeping Brewfile tiers
straight, guarding shell integrations, updating `docs/mapping.md` for managed
file changes, and not touching secrets.

## GitHub Copilot

[`.github/copilot-instructions.md`](../.github/copilot-instructions.md) gives
Copilot the same high-level repository rules and points it at `AGENTS.md`.
Keep it short; the detailed instructions live in `AGENTS.md`.

## Claude Code

A wrapper function in `.zshrc` sets the profile config directory before invoking `claude`, keyed to the chezmoi `profile` value:

- `CLAUDE_CONFIG_DIR=~/.config/claude/<profile>` — `personal` or `work`

### Shared base + profile files

Claude Code's global config is split into two layers:

- [`dot_config/claude/CLAUDE.shared.md`](../dot_config/claude/CLAUDE.shared.md) — the **shared base**, loaded for every session regardless of profile. Covers communication style, the tool environment Claude can assume, language-specific code-style preferences, and explicit anti-patterns ("don't suggest tmux, I use Zellij").
- `dot_config/claude/personal/CLAUDE.md` and `dot_config/claude/work/CLAUDE.md` — thin **profile files**. Each `@import`s the shared base and adds profile-specific posture (personal = experiment-friendly; work = PR-based and conservative). A templated `.chezmoiignore` applies only the file matching the active profile.

Edit via `chezmoi edit ~/.config/claude/CLAUDE.shared.md` (or the active profile file) to keep source in sync. Project-specific instructions go in `<project>/CLAUDE.md` and merge on top.

## Codex global instructions

[`dot_codex/AGENTS.md`](../dot_codex/AGENTS.md) maps to `~/.codex/AGENTS.md` and is loaded into every personal Codex session before project-level instructions. It mirrors the same personal defaults as `CLAUDE.md`: communication style, local tooling, backend stack preferences, code-style choices, and commit conventions. Project-specific Codex instructions go in `<project>/AGENTS.md` and layer on top.

## Local LLMs

Local AI tooling is an optional workstation feature:

```sh
dotfiles features enable ai
scripts/setup-local-llm.sh
```

The `ai` feature installs [`ollama`](https://docs.ollama.com/) for local model
serving and [`llm`](https://llm.datasette.io/) as a small Unix-style AI utility.
The setup script installs the `llm-ollama` plugin and pulls:

- `qwen2.5-coder:14b`
- `qwen3-coder:30b`
- `gpt-oss:20b`

Model downloads are intentionally separate from `brew bundle`: they are large,
machine-specific, and should not surprise-run during every dotfiles apply.

Use `llm` for shell-pipeline work, not as another coding agent. Good fits are
summarizing logs, turning diffs into release notes, extracting JSON from text,
or asking a quick local model question without starting Codex or Claude Code.
