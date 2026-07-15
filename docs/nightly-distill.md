# Nightly conversation distiller

The `nightlyDistill` module installs a launchd job that reads each day's Claude
Code conversations at 01:00 and distills them into durable, cross-machine
knowledge: file-based **memory** for future sessions and a dated **digest** for
you. Module selection and wiring follow the usual model
([packages.md](packages.md#optional-modules)); the rest of the AI setup is in
[ai.md](ai.md).

## What a run produces

| Output | Where | Synced by |
|---|---|---|
| Memory facts (dedup + supersede, so it self-heals) | global memory + each active project's `memory/` under `~/.config/claude/projects/` | private `claude-memory` git repo (global memory only) |
| Daily digest — highlights, per-project notes, memory changelog, open threads | Obsidian vault, `Claude Digests/<date>.md` | iCloud (the vault) |
| Weekly rollup (after each Sunday's distill) | `Claude Digests/<year>-W<ww> Weekly.md` | iCloud |
| Memory-GC pass (after each month's 1st) — merges near-duplicates, prunes superseded facts, repairs the index | global memory in place | same git repo |

## The pipeline

`distill.sh` orchestrates: `collect.py` slices the day's JSONL transcripts into
a compact conversation digest (per-message and total-size budgets, trimming
marked inline, never silent) → the reconcile prompt (`prompt.md`) runs via
`claude -p` (Sonnet) with file tools only → memory + digest are written → the
global memory repo is pulled/rebased, committed (unsigned) and pushed.

A scheduled run also **catches up**: it processes every missed day since
`state/last-success` (capped at 7 — launchd coalesces sleep-skipped firings,
but powered-off nights are otherwise gone), and fires the weekly/GC passes that
came due along the way. Failures exit non-zero and raise a macOS notification.

## Module wiring

Like every module, `nightlyDistill` is offered to **all profiles** in the
wizard's picker — profile defaults only decide whether it starts pre-checked
(it does for `personal`). Selecting it makes `chezmoi apply` lay down:

| Piece | Source |
|---|---|
| Scripts + prompts + README | `src/dot_config/claude/scripts/nightly-distill/` → `~/.config/claude/scripts/nightly-distill/` |
| launchd agent (templated for `$HOME`) | `src/Library/LaunchAgents/com.martin.claude-nightly-distill.plist.tmpl` |
| Agent (re)load + health warnings | `src/.chezmoiscripts/run_onchange_after_02f-nightly-distill.sh.tmpl` |
| Deploy-key SSH host alias (`github-claude-memory`) | `src/private_dot_ssh/config` |

The `claude` CLI itself comes from the `macApps` module's Brewfile.

## Three data channels, two machine-local secrets

The dotfiles repo is public, so the pieces travel by sensitivity:

- **Code** (scripts, prompts, plist) — this repo, gated by the module.
- **Digests** — the Obsidian vault, synced by iCloud.
- **Global memory** — a **private** GitHub repo (`claude-memory`); the job
  pulls before distilling and pushes after, so machines converge. Per-project
  memory stays local to each machine.

Two secrets never leave a machine and are re-created per machine: the headless
OAuth **token** (login Keychain) and the memory-repo **deploy key** (`~/.ssh`,
passphrase-less because the 1Password agent isn't available at 01:00 — which is
also why the nightly memory commits are unsigned).

## New machine setup

After `chezmoi apply` with the module selected, one guided command creates
whatever is missing (token → Keychain, deploy key → GitHub, memory repo →
cloned into place) and verifies connectivity:

```sh
~/.config/claude/scripts/nightly-distill/distill.sh --setup
```

It's idempotent — the apply hook nags about missing pieces until they exist.

## Usage & troubleshooting

| Command | Does |
|---|---|
| `distill.sh --status` | agent / token / memory-repo / last-run health at a glance |
| `distill.sh --dry-run` | full run into a sandbox (`last-dry-run/`), touches nothing real |
| `distill.sh --date 2026-07-14` | backfill one day (no state changes) |
| `distill.sh --week [2026-W28]` | weekly rollup only (default: last full week) |
| `distill.sh --gc` | memory-gardening pass on demand |
| `distill.sh --read` | open the latest digest in `bat` |
| `launchctl kickstart -k gui/$(id -u)/com.martin.claude-nightly-distill` | trigger the scheduled job now |

Logs live next to the scripts (`run.log`, `launchd.log`; auto-rotated), and the
deployed [README](../src/dot_config/claude/scripts/nightly-distill/README.md)
carries the full operational detail — tuning, manual setup fallback, and how
each digest section is meant to be read.
