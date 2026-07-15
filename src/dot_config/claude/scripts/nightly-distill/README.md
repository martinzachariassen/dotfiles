# Nightly conversation distiller

Every night at 01:00, distills the previous day's Claude Code conversations into:

- **Memory** — durable facts routed into the file-based memory system
  (project-specific → that project's `memory/`, personal → global memory),
  with dedup + supersede so it self-heals instead of piling up.
- **A dated digest** — a skimmable note in the Obsidian vault at
  `The Archive/Claude Digests/<date>.md`, plus a memory changelog.

## Pieces

| File | Role |
|------|------|
| `collect.py` | Slices a day's JSONL transcripts across all projects → compact digest (stdlib-only, runs on system python 3.9). |
| `prompt.md` | The reconcile instructions handed to `claude -p`. |
| `distill.sh` | Orchestrator. Collect → route → run Sonnet → write memory + digest → sync memory to its private git remote. |
| `com.martin.claude-nightly-distill.plist` | launchd agent (in `~/Library/LaunchAgents/`). |

## Portability — how this survives between machines

This whole component is **chezmoi-managed** in the (public) dotfiles repo, gated
behind the optional `nightlyDistill` module:

- The four files above live in `src/dot_config/claude/scripts/nightly-distill/`
  and the plist (templated for `$HOME`) in `src/Library/LaunchAgents/`. A
  `chezmoi apply` recreates them, and `run_onchange_after_02f-nightly-distill`
  (re)loads the launchd agent.
- **Nothing sensitive is committed.** Two secrets stay machine-local and are
  re-created per machine (steps below): the headless OAuth **token** (Keychain)
  and the memory-repo **deploy key** (`~/.ssh`).
- **The digests** already sync via iCloud (the Obsidian vault).
- **The global memory** (`~/.config/claude/projects/<home-slug>/memory/`) is its
  own git repo pointed at a **private** GitHub repo (`claude-memory`); `distill.sh`
  commits + pushes it after each run (see Step 4 in the script). Per-project
  memory stays local.

## One-time setup on a new machine

`chezmoi apply` with the `nightlyDistill` module selected lays down the scripts +
agent. Then do these three machine-local steps (the two secrets never travel):

### 1. Headless OAuth token → Keychain

launchd runs with no session auth, so the job needs a long-lived token (billed
against your Claude subscription, not separate API credits). Run interactively:

```sh
claude setup-token
security add-generic-password -s claude-nightly-distill -a "$USER" -w
# paste the token when prompted, press enter
```

`distill.sh` reads `CLAUDE_CODE_OAUTH_TOKEN` from this Keychain item at runtime.
To rotate: `security delete-generic-password -s claude-nightly-distill` then re-add.

### 2. Memory deploy key → `~/.ssh`

The nightly push must work without the 1Password SSH agent (unavailable at 01:00),
so use a dedicated, passphrase-less deploy key. The `github-claude-memory` Host
alias in `~/.ssh/config` (chezmoi-managed) already points at it:

```sh
ssh-keygen -t ed25519 -N '' -C "claude-memory deploy ($(hostname -s))" \
  -f ~/.ssh/claude_memory_ed25519
gh repo deploy-key add ~/.ssh/claude_memory_ed25519.pub \
  --repo martinzachariassen/claude-memory --allow-write \
  --title "claude-memory $(hostname -s)"
```

The private key file is **never committed** — it's machine-local, like the token.

### 3. Clone the memory repo into place

```sh
git clone git@github-claude-memory:martinzachariassen/claude-memory.git \
  "$HOME/.config/claude/projects/$(printf %s "$HOME" | tr / -)/memory"
```

That populates memory before the first run; the nightly job keeps it pushed.

## Usage

```sh
./distill.sh --dry-run           # sandbox run, touches nothing real; output in ./last-dry-run/
./distill.sh --dry-run --date 2026-07-15
./distill.sh                     # real run for yesterday (what launchd calls)
./distill.sh --date 2026-07-14   # backfill a specific day
./distill.sh --read              # open the latest digest in bat
```

Trigger the scheduled job by hand to test end-to-end:

```sh
launchctl kickstart -k gui/$(id -u)/com.martin.claude-nightly-distill
tail -f launchd.log
```

## Tuning

- **Skip projects**: set `DENY="-Users-martin-Developer-foo -Users-..."` near the
  top of `distill.sh` (space-separated slugs). All projects — including
  `~/Developer/work/` — are scanned by default. Work repos contribute like any
  other project; only genuinely sensitive proprietary specifics are kept out of
  *global* memory (they stay in the work project's own memory). See `prompt.md`.
- **Model**: `--model` flag or the `MODEL` default in `distill.sh` (Sonnet 5).
- **Logs**: `run.log` (orchestrator + claude output), `launchd.log` (raw launchd
  stdout/stderr, incl. auth-failure aborts).
