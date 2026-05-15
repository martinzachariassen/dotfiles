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

A wrapper function in `.zshrc` sets the personal config directory before invoking `claude`:

- `CLAUDE_CONFIG_DIR=~/.config/claude/personal`

### Global CLAUDE.md

[`dot_config/claude/personal/CLAUDE.md`](../dot_config/claude/personal/CLAUDE.md) is auto-loaded into every personal Claude Code session — covers communication style, the tool environment Claude can assume is available, language-specific code-style preferences, and explicit anti-patterns ("don't suggest tmux, I use Zellij"). Edit via `chezmoi edit ~/.config/claude/personal/CLAUDE.md` to keep it in sync with your source. Project-specific instructions go in `<project>/CLAUDE.md` and merge on top of this global one.

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
- `gemma3:12b`
- `llama3.1:8b`

Model downloads are intentionally separate from `brew bundle`: they are large,
machine-specific, and should not surprise-run during every dotfiles apply.

Use `llm` for shell-pipeline work, not as another coding agent. Good fits are
summarizing logs, turning diffs into release notes, extracting JSON from text,
or asking a quick local model question without starting Codex or Claude Code.
