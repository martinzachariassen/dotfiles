# AI tools

This repo is wired for three AI coding tools: Claude Code, GitHub Copilot, and
Codex. Each reads instructions in its own way; this page explains the layering
and how to change anything.

## Layering at a glance

Two layers, in order:

1. **User-level (per-machine, set by chezmoi)** — written into `$HOME` from this
   repo. Loaded once per session by each tool, before any project files.
   - Claude Code: `~/.config/claude/CLAUDE.md` (active profile body) +
     `@~/.config/claude/CLAUDE.shared.md` (recursive import at memory-load).
   - Codex: `~/.codex/AGENTS.md`.
   - Copilot: no user-level file here — relies on the repo-local layer.
2. **Repo-local (per-project)** — lives in this repo, ignored by chezmoi so it
   never lands in `$HOME`. Single source of truth: [`AGENTS.md`](../AGENTS.md).
   - Claude Code reads [`CLAUDE.md`](../CLAUDE.md), a one-line bridge that
     `@`-imports `AGENTS.md`. Without the bridge Claude Code wouldn't see
     `AGENTS.md` at all — it only auto-loads `CLAUDE.md`.
   - Copilot reads
     [`.github/copilot-instructions.md`](../.github/copilot-instructions.md),
     which points at `AGENTS.md`.
   - Codex auto-loads `AGENTS.md` natively.

Other projects work the same way — drop a `<project>/CLAUDE.md`,
`<project>/AGENTS.md`, or `.github/copilot-instructions.md` and they layer on
top of the user-level config.

## How to change AI behavior

| Want to change… | Edit | After |
|---|---|---|
| Style/conventions for all my AI sessions on this machine | `dot_config/claude/CLAUDE.shared.md` and/or `dot_codex/AGENTS.md` | `chez` |
| Behavior for one Claude profile (personal vs work) | `.chezmoitemplates/claude/<profile>.md` | `chez` |
| Rules for agents working in *this dotfiles repo* | `AGENTS.md` | nothing — repo-local, no apply step |

`CLAUDE.md` (repo root) and `.github/copilot-instructions.md` are bridges to
`AGENTS.md`. They rarely need edits — change `AGENTS.md` and every agent picks
it up.

## Repo-local instructions

[`AGENTS.md`](../AGENTS.md) is the canonical brief for AI agents working in
this dotfiles repo. It's deliberately tight — chezmoi source mapping, "edit
source not `$HOME`", Brewfile tiering, shell-integration guards, secrets, and
the verification commands. Both `AGENTS.md` and the project-level `CLAUDE.md`
are listed in `.chezmoiignore` so they stay repo-local; if `CLAUDE.md` ever
rendered into `$HOME` it would shadow the user-level
`~/.config/claude/CLAUDE.md`.

## GitHub Copilot

[`.github/copilot-instructions.md`](../.github/copilot-instructions.md) gives
Copilot the same high-level repository rules and points it at `AGENTS.md`.
Keep it short; the detailed instructions live in `AGENTS.md`.

## Claude Code: user-level

`.zshenv` exports `CLAUDE_CONFIG_DIR=~/.config/claude` so Claude Code (and any
subshell it spawns) reads its global config from the XDG location instead of
the default `~/.claude`. No per-invocation wrapper.

Two source files render that user-level config:

- [`dot_config/claude/CLAUDE.shared.md`](../dot_config/claude/CLAUDE.shared.md)
  — the **shared base**, loaded for every session regardless of profile.
  Communication style, tool environment Claude can assume, code-style
  preferences, anti-patterns ("don't suggest tmux, I use Zellij").
- [`dot_config/claude/CLAUDE.md.tmpl`](../dot_config/claude/CLAUDE.md.tmpl) —
  templated entry point. Uses
  `{{ includeTemplate (printf "claude/%s.md" .profile) . -}}` to pull the
  active profile body from
  [`.chezmoitemplates/claude/personal.md`](../.chezmoitemplates/claude/personal.md)
  or [`.chezmoitemplates/claude/work.md`](../.chezmoitemplates/claude/work.md).
  The body's first line is `@~/.config/claude/CLAUDE.shared.md`, so Claude
  Code layers the shared base in at memory-load time — no concat step, no
  generated file to accidentally edit in place.

Edit via `chezmoi edit ~/.config/claude/CLAUDE.shared.md`, or edit the profile
body directly in `.chezmoitemplates/claude/<profile>.md`, then run `chez`.
Switching profiles (`dotfiles profile set personal|work`) just changes which
body the template includes; the shared base is constant.

## Codex global instructions

[`dot_codex/AGENTS.md`](../dot_codex/AGENTS.md) maps to `~/.codex/AGENTS.md`
and is loaded into every personal Codex session before project-level
instructions. It mirrors the same personal defaults as the Claude shared base.
Project-specific Codex instructions go in `<project>/AGENTS.md` and layer on
top.

## Local LLMs

Local AI tooling ships in the `macApps` workstation module (on by default), so
no separate toggle is needed:

```sh
scripts/setup-ollama.sh          # starts Ollama as a brew service
```

The `macApps` feature installs [`ollama`](https://docs.ollama.com/) for local
model serving, plus the Codex, ChatGPT, Claude, and Claude Code apps (see
[`brewfiles/Brewfile.mac-apps`](../brewfiles/Brewfile.mac-apps)).
`scripts/setup-ollama.sh` runs Ollama as a background service via
`brew services` — it is idempotent and pulls no models.

Models are intentionally **not** downloaded for you: they are large and
machine-specific, so nothing surprise-runs during a dotfiles apply. Pull the
ones you want by hand:

```sh
ollama pull qwen2.5-coder:14b
ollama run  qwen2.5-coder:14b 'Explain this git error in one paragraph'
ollama list
```
