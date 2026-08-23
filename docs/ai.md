# AI tooling

Local and hosted AI, plus one shared set of global defaults that keeps every
assistant on the same page. Most of this rides on the `macApps` and
`claudePersona` modules — see [packages.md](packages.md#optional-modules).

## Apps & local models (macApps module)

Installed from [`Brewfile.mac-apps`](../packages/Brewfile.mac-apps):

- **Claude** (`cask "claude"`) — the Anthropic desktop app.
- **Claude Code** (`cask "claude-code"`) — the Anthropic CLI. The
  `anthropic.claude-code` VS Code extension is in the
  [extension list](../packages/vscode-extensions.txt) too.

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

`chezdistill` reads the Claude Code transcripts this machine wrote, distils them
into [TheArchive](https://github.com/martinzachariassen/TheArchive)'s
`30-Claude/` folder, and renders a size-capped `MAIN.md` that the persona above
`@`-imports — so what you and Claude worked out yesterday is in context tomorrow.
launchd runs it at 01:00 and the weekly review on Sunday at 02:00
([plists](../src/Library/LaunchAgents), registered by
[hook 06](../src/.chezmoiscripts/run_onchange_after_06-distill.sh.tmpl)).

**The model extracts and narrates; bash decides and writes.** Every judgement
that has to come out the same on two machines — hit counts, scope, what earns a
place in MAIN, what gets demoted — is computed in
[`scripts/lib/distill.sh`](../scripts/lib/distill.sh) from the extract corpus.
No model call in the system has write access: each one runs `--tools ""`, takes
its payload on stdin and returns schema-validated JSON.

### Three tiers, priced differently

| Tier | Lives in | Cost |
|---|---|---|
| `MAIN.md` | 6 KB cap, `@`-imported | paid for in **every** session, forever |
| `Topics/*.md` | unbounded | free — read only when Claude follows a wikilink |
| `Daily/`, `Weekly/` | append-only | for you; never read back by Claude |

Each item is split accordingly: a rule of at most 200 characters (enforced by the
JSON schema, not by asking) goes into MAIN, and the full explanation goes into
the topic note. Before that split the median rule was 300 characters and MAIN
held 13 of them; after it, 149 and 14 in half the bytes.

### Two machines, no lock

Transcripts don't sync, so both Macs must contribute. Each writes only
`.state/extracts/<date>/<hostname>.json` — separate paths, so they cannot
conflict — and whichever runs later re-renders the day from *everyone's*
extracts. A `## Sources` fingerprint in each report makes the second machine a
no-op: it sees its own hash already recorded and skips without calling the model.

The ledger is one file per entry (`.state/ledger/<id>.json`, id = hash of the
normalised text) rather than one big JSON, because a single file would conflict
in git on every run. And `hits` is *counted out* of the corpus, never
incremented, which is what makes re-running a day idempotent — and therefore
makes a late-waking second machine harmless.

### The promotion gate

Nothing reaches `MAIN.md` until it has been seen in **two distinct sessions**.
Single sightings sit in `Inbox/Candidates.md` where they affect nothing. It costs
a real insight a day; it makes it structurally impossible for one misreading in
one conversation to become a rule applied to every future session. Each daily
report opens with a `## MAIN.md changes` block, so auditing what changed in your
global instructions takes ten seconds.

### Scope

Origin is resolved at harvest time from the git remote (falling back to path
prefixes) and recorded per item, so `MAIN.md` renders `## Always`, `## Work only`
and `## Personal only` separately — a Storebrand convention never leaks into a
personal repo. Anything matching no pattern becomes `unknown`, which is blocked
from MAIN by two independent guards and surfaces in `chezdistill --status`.
Failing loudly beats filing work material as personal.

### Cost

Measured, not estimated: roughly **$0.16–0.23 per session** that yields items,
about $1–2 a night. `maxBudgetUsd` caps one call; `maxSpendUsd7d` is a rolling
ceiling summed across both machines and checked in preflight. A separate cheap
triage pass was tried and removed — it cost $0.05/session while every call
re-pays ~19k tokens of cached harness context, so the free `minTurns` gate does
that job instead.

### It never creates anything

Preflight requires the vault, its `.obsidian` directory, and `30-Claude/` to
exist already, and exits 0 otherwise. Without the `.obsidian` check an
uncloned vault looks like an empty directory and reports get written into a
dead end. Being offline is not an error: the work is committed locally and the
next run pushes it. Knobs live in
[`src/.chezmoidata/distill.toml`](../src/.chezmoidata/distill.toml).

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
> repo**; [`src/dot_config/claude/CLAUDE.md.tmpl`](../src/dot_config/claude/CLAUDE.md.tmpl)
> is the global defaults deployed to `$HOME` for use across **all** projects.
