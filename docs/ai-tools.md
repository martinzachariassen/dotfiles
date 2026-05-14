# AI tools

## Claude Code

A wrapper function in `.zshrc` sets the personal config directory before invoking `claude`:

- `CLAUDE_CONFIG_DIR=~/.config/claude/personal`

### Global CLAUDE.md

[`dot_config/claude/personal/CLAUDE.md`](../dot_config/claude/personal/CLAUDE.md) is auto-loaded into every personal Claude Code session — covers communication style, the tool environment Claude can assume is available, language-specific code-style preferences, and explicit anti-patterns ("don't suggest tmux, I use Zellij"). Edit via `chezmoi edit ~/.config/claude/personal/CLAUDE.md` to keep it in sync with your source. Project-specific instructions go in `<project>/CLAUDE.md` and merge on top of this global one.

## Codex global instructions

[`dot_codex/AGENTS.md`](../dot_codex/AGENTS.md) maps to `~/.codex/AGENTS.md` and is loaded into every personal Codex session before project-level instructions. It mirrors the same personal defaults as `CLAUDE.md`: communication style, local tooling, backend stack preferences, code-style choices, and commit conventions. Project-specific Codex instructions go in `<project>/AGENTS.md` and layer on top.
