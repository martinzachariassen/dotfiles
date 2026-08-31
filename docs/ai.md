# AI tooling

Local and hosted AI, plus one shared set of global defaults that keeps every
assistant on the same page. Most of this rides on the `macApps` and
`claudePersona` modules — see [packages.md](packages.md#optional-modules).

## Apps & local models (macApps module)

Installed from [`Brewfile.mac-apps`](../features/brew/Brewfile.mac-apps):

- **Claude** (`cask "claude"`) — the Anthropic desktop app.
- **Claude Code** (`cask "claude-code"`) — the Anthropic CLI. The
  `anthropic.claude-code` VS Code extension is in the
  [extension list](../features/vscode/extensions.txt) too.

## The global defaults (claudePersona module)

The file at
[`src/dot_config/claude/CLAUDE.md.tmpl`](../src/dot_config/claude/CLAUDE.md.tmpl) →
`~/.config/claude/CLAUDE.md` is the **project-agnostic** working agreement
Claude Code loads for **every** project on the machine: git/Conventional-Commit
conventions, code style, communication, verification posture, and secrets
rules. It carries **no stack or machine specifics** — those live in each
project's own `CLAUDE.md`, and project-level instructions always win over it.

`~/.config/claude/settings.json`
([source](../src/dot_config/claude/settings.json)) carries the Claude Code
harness config — model, theme, and a read-only permission allowlist (git
status/diff/log/show, `rg`, `ls`, `Read`, `Grep`, `WebSearch`).

## The nightly distiller (claudeDistiller module)

`chez distill` reads the Claude Code transcripts this Mac wrote and renders a
size-capped `MAIN.md` that the persona above `@`-imports — so what you and Claude
worked out yesterday is in context tomorrow. launchd runs it at 01:00.

It writes to two places, because the two have nothing in common. The memory
tier — `MAIN.md`, `Topics/`, `Candidates.md` — goes to
`~/.config/claude/memory`, beside the persona that imports it. The extract
corpus, the hand-written `Pinned.md`, the cursor, spend and run log go to
`~/.local/state/chezdistill`, in a git repo that pushes to a private corpus
you attach with `chez distill --remote <url>` — one private repo per profile,
never one shared, because `hits` is counted over the whole
corpus. That second one is the source
of truth: the memory tier is derived from it on every render, so it is the only
half worth backing up — and only the corpus and `Pinned.md` are tracked, because
the cursor, spend and run log describe one machine and nothing else.

There is no human-facing output. Nothing is written into an Obsidian vault or
anywhere else you would browse — the audience is Claude, and what it knows you
read with `chez distill --status`, `MAIN.md` or a note in `Topics/`. Because a job
with no output is a job you stop thinking about, `chez doctor` carries a
a chezdistill section: agent registered, last run recent and successful, `MAIN.md`
present and under its cap, corpus backed up — to its own profile's repo.

Its guiding rule is that **the model extracts while bash decides and writes**:
every judgement is computed in
[`features/distill/lib/`](../features/distill/lib), and no model call has
write access. Nothing reaches `MAIN.md` until it has been seen in two distinct
sessions, so a single misreading can't become a rule applied to every session.

What it captures is not in the code — it is one Markdown prompt,
[`skills/distill/SKILL.md`](../src/dot_config/claude/skills/distill/SKILL.md),
deployed to `~/.config/claude/skills/` and doubling as an interactive `/distill`
command. Editing it changes the job's behaviour without touching a line of bash —
it is the first place to look when the output is not what you wanted.

**Full guide: [distill.md](distill.md)** — turning it on, what happens each
night, the rubric and how to tune it, how to correct a wrong rule, cost, and
troubleshooting.

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
[`features/claude/tests/statusline.bats`](../features/claude/tests/statusline.bats).

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
> repo**; [`src/dot_config/claude/CLAUDE.md.tmpl`](../src/dot_config/claude/CLAUDE.md.tmpl)
> is the global defaults deployed to `$HOME` for use across **all** projects.
