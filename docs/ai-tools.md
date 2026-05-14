# AI tools

## Claude Code: work vs personal

A wrapper function in `.zshrc` routes `claude` based on PWD:

- Anywhere under `~/Dev/Work/` → uses `~/.claude` (work profile, managed by employer's tooling — see [Work setup](work-setup.md))
- Everywhere else → uses `~/.config/claude/personal`

Override with `cw` (work) or `cme` (personal) aliases, or `CLAUDE_PROFILE=work claude …` for one-off.

The CLI binary comes from the `cask "claude-code"` line in `brewfiles/Brewfile.work`; it is intentionally installed only for the work profile.

### Global CLAUDE.md

[`dot_config/claude/personal/CLAUDE.md`](../dot_config/claude/personal/CLAUDE.md) is auto-loaded into every personal Claude Code session — covers communication style, the tool environment Claude can assume is available, language-specific code-style preferences, and explicit anti-patterns ("don't suggest tmux, I use Zellij"). Edit via `chezmoi edit ~/.config/claude/personal/CLAUDE.md` to keep it in sync with your source. Project-specific instructions go in `<project>/CLAUDE.md` and merge on top of this global one.

## Codex global instructions

[`dot_codex/AGENTS.md`](../dot_codex/AGENTS.md) maps to `~/.codex/AGENTS.md` and is loaded into every personal Codex session before project-level instructions. It mirrors the same personal defaults as `CLAUDE.md`: communication style, local tooling, backend stack preferences, code-style choices, and commit conventions. Project-specific Codex instructions go in `<project>/AGENTS.md` and layer on top.
