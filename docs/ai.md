# AI tooling

Both local and hosted AI, plus one shared persona that keeps every assistant on
the same page. Most of this rides on the `macApps` and `claudePersona` modules —
see [packages.md](packages.md#optional-modules).

## Apps & local models (`macApps` module)

Installed from [`Brewfile.mac-apps`](../packages/Brewfile.mac-apps):

- **Ollama** (`brew "ollama"`) — a local model runner/server. It's installed but
  pulls **no models**. Start it with
  [`scripts/bin/setup-ollama.sh`](../scripts/bin/setup-ollama.sh) (registers it as
  a brew service), then `ollama pull <model>` for the ones you want.
- **Claude** (`cask "claude"`) — the Anthropic desktop app.
- **Claude Code** (`cask "claude-code"`) — the Anthropic CLI. The
  `anthropic.claude-code` VS Code extension is in the
  [extension list](../packages/vscode-extensions.txt) too.

## The shared persona (`claudePersona` module)

The persona at
[`src/dot_config/claude/CLAUDE.md`](../src/dot_config/claude/CLAUDE.md) →
`~/.config/claude/CLAUDE.md` is the cross-project working agreement Claude Code
loads for **every** project on the machine: stack (Kotlin/Java + Spring Boot),
communication style, operating posture, code conventions, and the
environment/secrets rules. Project-level instructions always win over it.

`~/.config/claude/settings.json`
([source](../src/dot_config/claude/settings.json)) carries the Claude Code
harness config — model, theme, and a read-only permission allowlist (git status/
diff/log, `rg`, `ls`, `Read`, `Grep`, `WebSearch`).

## The nightly distiller (`nightlyDistill` module)

Every night at 01:00, a launchd job distills the day's Claude Code conversations
into file-based memory (deduped, self-superseding) and a dated digest in the
Obsidian vault, with weekly rollups and a monthly memory-gardening pass on top.
The global memory syncs through a private git repo so what Claude learns about
you follows between machines. Full detail — pipeline, module wiring, the
one-command machine setup — in [nightly-distill.md](nightly-distill.md).

## One persona, two assistants

The **repo's own** contributor rules live in
[`.github/copilot-instructions.md`](../.github/copilot-instructions.md) — a single
source of truth shared by Claude Code and GitHub Copilot for work *in this repo*
(the `src/` split, chezmoi conventions, quality gates). The root
[`CLAUDE.md`](../CLAUDE.md) is a thin pointer to it, so both assistants read the
same rules rather than drifting apart. Keep the two in sync when either changes.

> Not to be confused: `.github/copilot-instructions.md` is guidance for AI editing
> **this repo**; `src/dot_config/claude/CLAUDE.md` is the persona deployed to
> `$HOME` for use across **all** your projects.
