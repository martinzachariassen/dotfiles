# AI tooling

Local and hosted AI, plus one shared set of global defaults that keeps every
assistant on the same page. Most of this rides on the `macApps` and
`claudePersona` modules — see [packages.md](packages.md#optional-modules).

## Apps & local models (macApps module)

Installed from [`Brewfile.mac-apps`](../packages/Brewfile.mac-apps):

- **Ollama** (`brew "ollama"`) — a local model runner/server. Installed but
  pulls **no models**. Start it with
  [`scripts/bin/setup-ollama.sh`](../scripts/bin/setup-ollama.sh) (registers
  it as a brew service), then `ollama pull <model>` for the ones you want.
- **Claude** (`cask "claude"`) — the Anthropic desktop app.
- **Claude Code** (`cask "claude-code"`) — the Anthropic CLI. The
  `anthropic.claude-code` VS Code extension is in the
  [extension list](../packages/vscode-extensions.txt) too.

## The global defaults (claudePersona module)

The file at
[`src/dot_config/claude/CLAUDE.md`](../src/dot_config/claude/CLAUDE.md) →
`~/.config/claude/CLAUDE.md` is the **project-agnostic** working agreement
Claude Code loads for **every** project on the machine: git/Conventional-Commit
conventions, code style, communication, verification posture, and secrets
rules. It carries **no stack or machine specifics** — those live in each
project's own `CLAUDE.md`, and project-level instructions always win over it.

`~/.config/claude/settings.json`
([source](../src/dot_config/claude/settings.json)) carries the Claude Code
harness config — model, theme, and a read-only permission allowlist (git
status/diff/log, `rg`, `ls`, `Read`, `Grep`, `WebSearch`).

## One rulebook, two assistants

The **repo's own** contributor rules live in [`../CLAUDE.md`](../CLAUDE.md)
— the single source of truth for work *in this repo* (the `src/` split,
chezmoi conventions, quality gates, git/PR policy). Claude Code reads it
natively; [`.github/copilot-instructions.md`](../.github/copilot-instructions.md)
is a thin pointer that mirrors the non-negotiables inline so GitHub Copilot
lands on the same rules. Keep that crib in sync if the non-negotiables
change.

> [!NOTE]
> Two files named `CLAUDE.md`, not to be confused: the root
> [`CLAUDE.md`](../CLAUDE.md) is the contributor rulebook for editing **this
> repo**; [`src/dot_config/claude/CLAUDE.md`](../src/dot_config/claude/CLAUDE.md)
> is the global defaults deployed to `$HOME` for use across **all** projects.
