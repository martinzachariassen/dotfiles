# The nightly distiller

Turns past Claude sessions into the `MAIN.md` every future session loads. Two
destinations, a corpus with its own identity, and no human-facing output.

Gated by the `claudeDistiller` module. Full guide:
[docs/distill.md](../../docs/distill.md).

## Verbs

- `chez distill` — Distil Claude conversations into the MAIN.md Claude loads.

Read-only and free: `--status`, `--stats`, `--runs [N]`, `--logs [N] [-f]`.
Writing: `--setup`, `--render`, `--since 7d`, `--undo`, `--remote [URL|none]`.

## The guiding rule

**The model extracts, bash decides and writes.** Every judgement — hit counts,
what earns a place in `MAIN.md`, what gets demoted — is computed in
[`lib/`](lib), and every `claude -p` call runs `--tools ""` with no write access.

`hits` is **derived** from the extract corpus, never incremented. That is what
makes `--render`, `--since 7d` and a repeated nightly run idempotent, and it is
why `--undo` reverts the corpus and re-renders rather than reverting the
rendered files.

Don't move a decision into a prompt.

## Layout

[`cli.sh`](cli.sh) parses the flags. [`lib.sh`](lib.sh) is the only entry point
into the engine: source it and you have all of it. The engine itself is fifteen
modules under [`lib/`](lib), split along the seams its own section banners
already marked when it was one 2,605-line file.

| Module | Owns |
|---|---|
| `config.sh` | Where everything lives, portable dates, the harvest cursor |
| `preflight.sh` | Every reason a run cannot proceed |
| `harvest.sh` | Which transcripts are new since the cursor |
| `model.sh` | The only place that calls the model — plus its schema and rubric |
| `spend.sh` | What a run cost, and the rolling budget window |
| `runlog.sh` | `runs.jsonl` — a row per night |
| `ledger.sh` | The extract corpus, and the hit counts derived from it |
| `render.sh` | `MAIN.md` and `Topics/` |
| `backup.sh` | The state repo, and pushing it somewhere |
| `corpus.sh` | `corpus.json` — a corpus states its own identity |
| `attach.sh` | `--remote`: attaching, adopting, refusing |
| `remote.sh` | Which corpus is this Mac's |
| `status.sh` | `--status` and `--logs` |
| `reports.sh` | `--runs` and `--stats` |
| `nightly.sh` | What launchd invokes at 01:00 |

`backup.sh` is a general git-backup engine and stays here rather than moving to
`core/`: nothing else uses it, and `core/` is for what no single feature owns.

Its data is `src/.chezmoidata/distill.toml`; its agent is registered by
`run_onchange_after_06-distill`, which hashes the plist and `cli.sh` — the two
things registration actually depends on — and not the engine, since launchd
invokes `cli.sh` by path each night.

## Two destinations, and only one is worth backing up

**`~/.config/claude/memory`** — `MAIN.md`, `Topics/`, `Candidates.md`. Derived
and disposable; re-renders from the corpus at any time. Read by Claude and by
nothing else.

**`~/.local/state/chezdistill`** — the extract corpus, the hand-written
`Pinned.md`, the cursor, spend and run log. The source of truth, in a git repo
you attach with `chez distill --remote <url>`.

Inside state the split repeats: **only `extracts/` and `Pinned.md` are tracked.**
`cursor.json`, `spend.jsonl`, `runs.jsonl` and `logs/` describe one machine and
are append-only — tracking them makes two Macs conflict on every line and
silently kills the backup.

**No corpus URL belongs in this repo — it is public.** Where a Mac backs up is a
prompted answer, blank by default, and it is a *seed*: it points a state repo
that has no origin, and is never consulted again. `git remote origin` is the
authority thereafter. A seed that disagrees with origin is surfaced by
`--status`, never silently obeyed.

## A corpus states its own identity, and a URL is not one

Every corpus carries a tracked `corpus.json` — `id` + `scope`, never a URL or
anything derived from one — written once at creation and never rewritten.

`scope` is the leak boundary and is checked from the **local** copy, so the
nightly guard stays offline; the remote's copy is read only at attach time. A
matching `id` at a different URL means the repo moved, so adopt it. A different
`scope` is a hard stop. A corpus with no stamp predates the file: adopt it,
stamp it, and say that nothing could check it.

The scope is a free-text label, prompted as `memoryScope` and read by
`distill_scope`. Schema 1 spelled it `profile`, back when the repo had a profile
enum to borrow it from; schema 2 writes `scope` and both are read, so an existing
corpus keeps its identity and no Mac has to re-clone.

The corpus is sharded per host (`extracts/<date>.<host>.json`) so two Macs in the
*same* scope can share a remote. Across scopes they must not, since `hits`
counts sightings over the whole corpus — one private repo each. Read the date
with `distill_extract_date`, never by stripping `.json`, so pre-sharding files
still work.

Joining two corpora is a **data replay, not a history merge**: origin's history
is the base and this Mac's shards land on top, unioned per shard, which is safe
only because `hits` counts distinct sessions.

## A backup reports what the remote HAS, never what it is called

Naming an origin is not evidence of a push, and treating it as evidence is how
two days of rejected pushes once rendered as `✓ backup`. The verdict is computed
once in `distill_backup_state` — `HEAD` against the remote-tracking ref, offline
— and only *rendered* by `--status` and `chez doctor`, never re-derived in
either, or the two drift and the weaker one wins.

Reconciling is a **merge, never a rebase**: a stopped rebase leaves a detached
`HEAD` that silently accepts commits forever, so a repo found mid-rebase or
detached stops before committing rather than being repaired by guesswork.

Name the branch explicitly in every git call — `git init` follows
`init.defaultBranch`, which is set on this machine and unset in CI.

## No human-facing output, and no vault

It produced daily and weekly notes in Obsidian once; that half was removed
deliberately. The boundary is a *written* destination: no generated notes, no
digest, no file anyone but Claude reads.

Asking it questions from a terminal is fine, and is how you read what it knows.
The one concession is a `chez distill` section in `chez doctor` — passive
liveness only, read-only, no API calls. Without it, a job that silently stopped
running would leave `MAIN.md` merely not growing, and nothing would say so.
