# Nightly conversation distiller

Every night at 01:00, distills each day's Claude Code conversations into:

- **Memory** — durable facts routed into the file-based memory system
  (project-specific → that project's `memory/`, personal → global memory),
  with dedup + supersede so it self-heals instead of piling up. The global
  memory syncs through a private git repo and follows you between machines.
- **A dated digest** — a skimmable note in the Obsidian vault at
  `The Archive/Claude Digests/<date>.md`: highlights, per-project notes, a
  memory changelog, and **open threads** carried forward day to day.
- **Periodic passes** — after each Sunday's distill, a weekly rollup
  (`<year>-W<ww> Weekly.md`); after each month's 1st, a memory-GC pass that
  merges near-duplicates, prunes superseded facts, and repairs the index.

A scheduled run catches up every missed day since the last success (capped at
7), so a laptop that slept or sat powered off for a few nights heals itself.

## Pieces

| File | Role |
|------|------|
| `collect.py` | Slices a day's JSONL transcripts across all projects → compact digest (stdlib-only, runs on system python 3.9). Budgets: 2k chars/message, ~400k chars/day total — over-budget days are trimmed proportionally with inline markers, never silently. |
| `prompt.md` | The reconcile instructions handed to `claude -p` for the daily pass. |
| `prompt-weekly.md` | The weekly-rollup instructions. |
| `prompt-gc.md` | The monthly memory-gardening instructions. |
| `distill.sh` | Orchestrator: collect → route → run Sonnet → write memory + digest → sync memory. Also `--status`, `--setup`, and the periodic-pass triggers. |
| `com.martin.claude-nightly-distill.plist` | launchd agent (in `~/Library/LaunchAgents/`). |
| `state/`, `run.log`, `launchd.log`, `last-dry-run/` | Runtime artifacts (auto-rotated logs, catch-up state) — machine-local, never committed. |

## Usage

```sh
./distill.sh --status            # agent / token / memory-repo / last-run health
./distill.sh --dry-run           # sandbox run, touches nothing real; output in ./last-dry-run/
./distill.sh --dry-run --date 2026-07-15
./distill.sh                     # scheduled run (what launchd calls): catch up + periodic passes
./distill.sh --date 2026-07-14   # backfill one specific day (no state changes)
./distill.sh --week              # weekly rollup for the last full ISO week
./distill.sh --week 2026-W28     # …or a specific week
./distill.sh --gc                # memory-gardening pass on demand
./distill.sh --read              # open the latest digest in bat
```

Trigger the scheduled job by hand to test end-to-end:

```sh
launchctl kickstart -k gui/$(id -u)/com.martin.claude-nightly-distill
tail -f launchd.log
```

Failures exit non-zero and raise a macOS notification, so a broken night is
visible in the morning; `--status` shows the last exit code launchd saw.

## Portability — how this survives between machines

This whole component is **chezmoi-managed** in the (public) dotfiles repo,
gated behind the optional `nightlyDistill` module — see
`docs/nightly-distill.md` in the repo for the full picture:

- The scripts/prompts/this README live in
  `src/dot_config/claude/scripts/nightly-distill/` and the plist (templated for
  `$HOME`) in `src/Library/LaunchAgents/`. A `chezmoi apply` recreates them, and
  `run_onchange_after_02f-nightly-distill` (re)loads the launchd agent and nags
  about missing per-machine pieces.
- **Nothing sensitive is committed.** Two secrets stay machine-local and are
  re-created per machine: the headless OAuth **token** (Keychain) and the
  memory-repo **deploy key** (`~/.ssh`).
- **The digests** already sync via iCloud (the Obsidian vault).
- **The global memory** (`~/.config/claude/projects/<home-slug>/memory/`) is
  its own git repo pointed at a **private** GitHub repo (`claude-memory`).
  Every real run pulls/rebases before distilling and commits + pushes after
  (unsigned — the 1Password signing agent isn't around at 01:00), so machines
  converge. Per-project memory stays local.

## One-time setup on a new machine

After `chezmoi apply` with the `nightlyDistill` module selected, run:

```sh
./distill.sh --setup
```

It's interactive, idempotent, and detect-then-act: it walks the token
(`claude setup-token` → Keychain), the deploy key (`ssh-keygen` +
`gh repo deploy-key add --allow-write`), and the memory-repo clone, then
verifies connectivity (which also seeds `known_hosts` so the first headless run
can't stall on a host-key prompt). Re-run it any time; `--status` shows what's
missing.

<details>
<summary>Manual fallback (what --setup does, step by step)</summary>

1. **Headless OAuth token → Keychain.** launchd runs with no session auth, so
   the job needs a long-lived token (billed against your Claude subscription):

   ```sh
   claude setup-token
   security add-generic-password -s claude-nightly-distill -a "$USER" -w
   # paste the token when prompted, press enter
   ```

   To rotate: `security delete-generic-password -s claude-nightly-distill`,
   then re-add.

2. **Memory deploy key → `~/.ssh`.** The nightly push must work without the
   1Password SSH agent, so use a dedicated passphrase-less deploy key. The
   `github-claude-memory` host alias in `~/.ssh/config` (chezmoi-managed)
   already points at it:

   ```sh
   ssh-keygen -t ed25519 -N '' -C "claude-memory deploy ($(hostname -s))" \
     -f ~/.ssh/claude_memory_ed25519
   gh repo deploy-key add ~/.ssh/claude_memory_ed25519.pub \
     --repo martinzachariassen/claude-memory --allow-write \
     --title "claude-memory $(hostname -s)"
   ```

3. **Clone the memory repo into place:**

   ```sh
   git clone git@github-claude-memory:martinzachariassen/claude-memory.git \
     "$HOME/.config/claude/projects/$(printf %s "$HOME" | tr / -)/memory"
   ```

</details>

## Tuning

- **Skip projects**: set `DENY="-Users-martin-Developer-foo -Users-..."` near
  the top of `distill.sh` (space-separated slugs). All projects — including
  `~/Developer/work/` — are scanned by default; only genuinely sensitive
  proprietary specifics are kept out of *global* memory (they stay in the work
  project's own memory). See `prompt.md`.
- **Model**: `--model` flag or the `MODEL` default in `distill.sh` (Sonnet 5).
- **Catch-up window**: `CATCHUP_CAP` in `distill.sh` (default 7 days); older
  gaps backfill manually via `--date`.
- **Input budget**: `TOTAL_BUDGET_CHARS` in `collect.py`.
- **Self-tuning**: the daily digest's *Distiller notes* section is where the
  distiller flags recurring input noise or prompt friction it noticed — when a
  note keeps appearing, fold the fix back into `collect.py`/`prompt.md`.
- **Logs**: `run.log` (orchestrator + claude output), `launchd.log` (raw
  launchd stdout/stderr, incl. auth-failure aborts). Both auto-rotate to the
  last 500 lines.
