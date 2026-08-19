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
status/diff/log/show, `rg`, `ls`, `Read`, `Grep`, `WebSearch`).

## The status line

[`executable_statusline.sh`](../src/dot_config/claude/executable_statusline.sh)
renders the two-line bar under the prompt. Claude Code pipes it a JSON payload
on stdin ([schema](https://code.claude.com/docs/en/statusline)); the script
parses every field in **one** `jq` call and does all float math there, so bash
only ever sees integers. Git state is a separate cost, so it's cached per
session in `$TMPDIR` for 5s.

```
Opus 5 MAX ⚡ · 📁 dotfiles · 🌿 main ~2 ?1 ⇡1 +120/-34 · PR #94
███████░░░░░░░ 48% 96k/1.0M · 💰 $1.24 $1.59/h · ⏱ 12m/47m · 5h 62% ↻1h42m · 7d 41% ↻4d5h
```

Line 1 is **identity**: model, effort level, then mode flags that appear *only*
when the session deviates from its defaults — `⚡` fast mode, `1M` for having
crossed 200k tokens into premium-tier pricing, `🧠off` for disabled thinking,
plus vim mode, `--agent` name, a non-default output style, a `/rename`d session
(`🏷`), and `/add-dir` count. Then cwd, git state with the session's diff tally,
and the PR badge (OSC 8 hyperlink — Cmd-click it).

Line 2 is **budget**, and the two clocks are the part worth explaining:

- `⏱ 12m/47m` — `total_api_duration_ms` over `total_duration_ms`: time actually
  spent waiting on the model, versus how long the session has been open. The
  second number alone is just process uptime and counts while you're at lunch,
  which is why it's shown as a ratio rather than on its own.
- `↻1h42m` — `rate_limits.*.resets_at` as a countdown. A quota percentage can't
  be acted on without knowing when the window rolls over; `5h 93% ↻3m` and
  `5h 93% ↻4h` call for opposite decisions.

`💰 $1.24 $1.59/h` is cumulative cost plus burn rate, the latter suppressed for
the first two minutes where it's pure noise. Behavior is covered by
[`tests/statusline.bats`](../tests/statusline.bats).

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
