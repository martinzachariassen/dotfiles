# The nightly distiller

`chezdistill` reads the Claude Code transcripts this Mac wrote, renders a
size-capped `MAIN.md` that every future Claude session loads, and writes the
reports you read into the Obsidian vault. What you and Claude worked out
yesterday is in context tomorrow.

It is the one verb that talks to a paid API on a timer, and the one that writes
outside `$HOME`. Both facts shape the rules below.

Gated on the `claudeDistiller` module. Verb reference in
[commands.md](commands.md); the persona it feeds is in [ai.md](ai.md).

## Three destinations

The three things this job produces have nothing in common, so they live apart.

| Where | What | Git |
|---|---|---|
| `~/.config/claude/memory/` | `MAIN.md`, `Pinned.md`, `Topics/`, `Candidates.md` | none — rendered from state |
| `~/.local/state/chezdistill/` | the extract corpus, `Pinned.md`, cursor, spend, run log, logs | a local repo, remote optional |
| `~/Documents/TheArchive/30-Claude/` | `README.md`, `Decisions.md`, `Open threads.md`, `Daily/`, `Weekly/`, `Runs.md` | the vault's own repo, pushed |

Three consequences worth knowing before changing anything:

**The memory tier does not depend on the vault.** The persona `@`-imports
`MAIN.md`, and a laptop with TheArchive unmounted still has to get its rules. So
a missing vault costs you that day's report and nothing else — the job says so,
renders the memory, and exits 0.

**The extracts are the memory.** Every rule, hit count and date is derived from
them, so they are what a replacement Mac actually needs. They are in a local repo so `--undo` works, and
that repo has no remote so there is nothing to leak into.

**`Topics/` sits next to `MAIN.md`, not in the vault.** It is the other half of
each rule, and MAIN carries one line pointing at it. Put it in the vault and
Claude cannot read it.

## Turning it on

One command, from a checkout of this repo:

```sh
bash ~/Developer/personal/dotfiles/scripts/bin/distill.sh --setup
```

It goes through the full path — check the vault, create `30-Claude/`, migrate an
older single-folder layout if it finds one, add `claudeDistiller` to the module
list, apply, register both launchd agents, seed a `MAIN.md` so the persona's
`@`-import resolves from the first session rather than after the first successful
night, then print `--status`. Every step is confirmed and every step is
idempotent, so re-running it on a machine that is already set up just reports
green. It makes no API calls.

The long form of the script path is not an accident: the `chezdistill` shell verb
is gated on the module, so until `--setup` has turned the module on, the verb does
not exist. Afterwards, `chezdistill --setup` works normally.

**What `--setup` will not do is create the vault.** The rule exists because a
vault that was never cloned — or is not mounted right now — looks exactly like an
empty directory, and reports written into one would vanish. That guard is the
vault + `.obsidian` check: no vault, or no `.obsidian` inside it, and setup
refuses and exits 1 having changed nothing. Clone or mount TheArchive first.

The memory dir and the state dir are a different matter. They are ordinary local
directories with no mount to be wrong about, so they are simply created.

### Migrating from the single-folder layout

If `30-Claude/` still holds `.state/`, `MAIN.md`, `Topics/` and `Inbox/`, that is
the pre-split layout, from when two machines merged through the vault's git repo.
`--setup` offers to move it:

- `.state/` → `~/.local/state/chezdistill/`, with `extracts/<date>/<host>.json`
  flattened to `extracts/<date>.json` and the per-host `spend/` and `runs/` files
  concatenated into `spend.jsonl` and `runs.jsonl`
- `MAIN.md`, `Pinned.md`, `Topics/`, `Inbox/Candidates.md` →
  `~/.config/claude/memory/`
- `Daily/`, `Weekly/` and `Runs.md` stay where they are

It **copies**; nothing in the vault is deleted. Once a run looks right, delete the
old copies by hand — a half-migrated vault you cannot inspect is worse than a
duplicated one.

### Doing it by hand

1. **Create the folder in Obsidian**: `30-Claude` at the vault root.
2. **Enable the module**: `chezsetup`, tick *claudeDistiller*. It's in the base
   profile, so new machines get it by default.
3. **Apply**: `chezup`. Hook 06 registers both launchd agents.
4. **Check**: `chezdistill --status`.

## Running it now

Nothing has to wait for 01:00 — the flags below are the same code path launchd
takes, just started by hand:

```sh
chezdistill              # the nightly job, right now
chezdistill -n           # preview: what it would read and run, no model calls
chezdistill --since 7d   # backfill the last week
chezdistill --weekly     # the weekly review and compaction
chezdistill --render     # rebuild every generated note from the corpus, free
chezdistill --status     # where things live, MAIN size vs cap, spend, last run
chezdistill --undo       # revert the last state commit and re-render
```

`-n` first is the cheap habit: it prints the sessions that would be read and the
calls that would be made without spending anything. A repeat run of a day already
distilled is a no-op — the source fingerprint matches and no model is called — so
running it by hand does not double-bill you for the night.

## What happens each night

```
01:00  launchd fires
  │
  ├─ PREFLIGHT   memory + state paths; vault? .obsidian? 30-Claude? writable?
  │                under the spend ceiling?
  │                no vault → say so, skip the reports, keep going
  ├─ PULL        git pull --rebase in the vault  (failing here is fine)
  ├─ CURSOR      read cursor.json, else 24h ago
  ├─ HARVEST     transcripts touched since, subagent files excluded
  ├─ FILTER      keep typed human turns + assistant prose; drop tool traffic,
  │                thinking, sidechains, harness noise        ~16x smaller
  ├─ GATE        fewer than minTurns typed turns → skipped, free, no API call
  ├─ MAP         one model call per surviving session → items as JSON
  │                → state/extracts/<date>.json — a failed write here holds the
  │                  cursor back: the calls are billed, no re-run recovers them
  ├─ SOURCE      already reflected in the report? → done, no further calls
  ├─ NARRATE     one model call per date → the ## Summary prose
  ├─ RENDER      bash builds MAIN.md, Topics/, Candidates.md, the daily report
  ├─ RECORD      append the run to state/runs.jsonl, render Runs.md
  ├─ GITLEAKS    over state, memory AND the vault folder → abort on any hit
  └─ COMMIT      state locally; the vault committed and pushed
```

Every step from RECORD down runs whether the run succeeded or failed — a failure
that leaves no trace is a failure you find out about weeks later. A run that
harvested nothing still commits, so "nothing ran last night" and "nothing was
worth keeping last night" stay distinguishable.

The weekly job (Sunday 02:00) is the same shape, writing `Weekly/YYYY-Www.md`.

**The model extracts and narrates; bash decides and writes.** Every judgement —
hit counts, what enters MAIN, what gets demoted — is computed in
[`scripts/lib/distill.sh`](../scripts/lib/distill.sh). No model call has write
access: each runs `--tools ""`, takes its payload on stdin, returns
schema-validated JSON. Keeping the decisions in bash is what makes a re-run of an
already-distilled day produce a byte-identical file and therefore no commit.

## Two audiences

`MAIN.md` answers *what should Claude know*. `Decisions.md` and `Open threads.md`
answer *what did I settle, and what do I still owe*. They are built from the same
corpus and they behave differently on purpose.

**The promotion gate does not apply to the second pair.** The gate exists because
`MAIN.md` is loaded into every session unattended, so one misreading becoming a
global rule is a real cost. Neither half of that holds for a note you open
yourself: a decision made once is still a decision, an open thread mentioned once
is still open, and you have the judgement to discard a bad entry. Gating them
would have meant 37 of 39 items reaching nothing a person ever reads.

`Open threads.md` is **rebuilt** every run rather than accumulated. An entry drops
off when it stops being extracted — from here, that is what closing it looks like.

The extraction rubric carves both out of the "still true in a month" test it
applies to everything else. An open thread is worth knowing *tomorrow*, which is
exactly the horizon that test rejects — before the carve-out, the corpus held
nineteen gotchas and zero open threads.

## Three tiers, priced differently

| Tier | Where | What it costs |
|---|---|---|
| `MAIN.md` | 6 KB cap, `@`-imported by the persona | paid for in **every** session, forever |
| `Topics/*.md` | unbounded, beside MAIN | free — read only when Claude looks a rule up |
| `Daily/`, `Weekly/`, `Runs.md` | the vault, append-only | for you; Claude never reads them back |

Each extracted item is split along that seam: a rule of **at most 200 characters**
goes into MAIN, the full explanation goes into the topic note. The limit is in the
JSON schema, not in the prompt — asking the model to be brief doesn't work, and
before the cap the median rule was 300 characters and MAIN held 13 of them.

`MAIN.md` carries exactly one line connecting the two tiers, naming the directory
and the `Topics/<Topic>.md` scheme. One pointer rather than a path per rule:
per-rule links measured at roughly a sixth of the whole byte budget, to say the
same thing 30 times.

`Topics/` is deliberately wider than MAIN — it holds every derived entry, including
ones still waiting for a second sighting. Once you have gone looking for a topic,
the rule that hasn't been promoted yet is still worth reading.

Eviction moves entries from tier 1 to tier 2. It never deletes.

## What you'll actually read

### `~/.config/claude/memory/MAIN.md` — generated, do not edit

```markdown
<!-- Generated by chezdistill. Do not edit: edit Pinned.md instead. -->

Fuller explanations for the rules below live beside this file, in
`~/.config/claude/memory/Topics/<Topic>.md`.

# Pinned

- Never force-push to main.

## Learned from past sessions

- Use `rg`, never `grep`.
- Bean validation annotations never fire on non-nullable Kotlin constructor properties.
```

### `Topics/Jackson.md` — the same rule, with the detail

```markdown
## Spring Boot 4 uses Jackson 3 with package root tools.jackson.databind…

When catching Jackson deserialization causes (MismatchedInputException,
InvalidFormatException) to build detailed 400 error bodies, import from
tools.jackson.databind.exc. Relevant when Boot 4 + Jackson 3 is on the
classpath; older Spring Boot versions still use com.fasterxml.

*2 hit(s) · last seen 2026-08-22*
```

### `Daily/2026-08-22.md` — in the vault

Opens with `## MAIN.md changes` — every rule added or demoted since the last
run, truncated to one line each. **That block is the point:** ten seconds a day tells you everything
that changed in the instructions every session now loads. Then a `## Summary`
narrative, then the items by kind, then the source fingerprint.

### `README.md` — the folder explaining itself

Generated. What each note is, how an entry gets here, and how to overrule one,
with wikilinks to the rest. Everything else about this system is documented in
the dotfiles repo, which is not where you are when you are reading your notes.

### `Decisions.md` and `Open threads.md`

What was settled and what is still owed, both ungated, both linked to their topic.
`Topics/` is symlinked into the vault so those links resolve in Obsidian without
a second copy on disk; the symlink is gitignored, because a committed one is an
absolute path that is wrong on every other machine.

### `Candidates.md`

Everything that hasn't earned a place in MAIN: seen only once, or past the gate
but gone stale. Entries here affect nothing.

### `Runs.md` — did it run, and did it work?

Every nightly and weekly run, newest first:

```markdown
## Last 7 days

- 9 run(s): 8 ok, 1 failed
- 11 of 34 session(s) distilled, 41 item(s)
- $1.87 spent

## Recent runs

| Ended | Mode | Sessions | Items | Cost | MAIN | Result |
|---|---|---|---|---|---|---|
| 2026-08-24 01:03 | daily | 3/7 | 12 | $0.42 | 5.1K | ok |
| 2026-08-23 01:02 | daily | 0/4 | 0 | $0 | 5.0K | **failed** |
```

**`0/7` is the number to read.** Seven sessions seen and none distilled looks
like a broken job; the `## Last run in detail` block is what tells you it was six
sessions under `minTurns` and one with nothing durable in it — free, and working
as designed. Times are UTC.

The records behind it are `runs.jsonl`, kept for `runRetentionDays`.
`chezdistill --status` prints the newest one; `--render` rebuilds the note from
the records for free.

## The promotion gate

**Nothing reaches `MAIN.md` until it has been seen in two distinct sessions.**

This costs a genuine insight a day. In exchange, one misreading in one
conversation cannot become a rule applied to every future session — which matters
because `MAIN.md` is `@`-imported everywhere and the job runs unattended.
`minHits` in `distill.toml` if you want it looser.

`hits` counts distinct sessions and is **derived from the extract corpus, never
incremented.** Incrementing would double-count the moment a day is re-run;
deriving is what makes `--since 7d`, `--render` and a repeated nightly run all
safe to fire at will.

## Correcting it

The generated files are not the place to push back — the next run overwrites them
from the corpus. Use these instead:

| Situation | What to do |
|---|---|
| A rule is wrong or badly worded | Write the correct one in `~/.config/claude/memory/Pinned.md`. It is prepended into `MAIN.md` verbatim, never demoted, never rewritten. |
| Last night's run made a mess | `chezdistill --undo` reverts the state repo's last commit and re-renders the memory from it. |
| You edited the corpus or `Pinned.md` | `chezdistill --render` rebuilds every generated note, daily reports included. No API calls — the narratives are cached beside the extracts. |
| An entry should be gone entirely | Delete its sightings from `extracts/<date>.json`. Everything about an entry is derived from the corpus, so that is the only place it exists. |

`--undo` reverts the corpus rather than the rendered files, because
`MAIN.md`, `Topics/` and `Candidates.md` are a pure function of them. Reverting
the output instead would leave it free to disagree with the corpus on the next
run.

## Sleep, wake, and the cursor

launchd fires a missed `StartCalendarInterval` **on wake**, and **coalesces**
several missed firings into one run — not three runs after three sleeping nights.
Powered off, it fires after the next login.

That's why the job tracks a cursor (`cursor.json`) rather than asking "what
happened yesterday?". A job built on "yesterday" loses everything the machine
slept through; "what has happened since I last read?" cannot. A run spanning
several days writes one `Daily/` note per calendar day.

The file scan is widened from the same cursor, and that is load-bearing: the
harvester only opens transcripts whose **mtime** is newer than the cursor (minus a
day of slack), because a transcript's mtime moves whenever a turn is appended, so
an older one really can hold nothing new. Pin that window to a constant instead
and the cursor is quietly defeated — the sessions from the nights the machine
slept are exactly the ones whose files stopped being written, and `--since 7d`
would read only the last two days of them while reporting success.

`pmset repeat wake` would force an exact 01:00, but it also wakes the laptop in
your bag. Not used here.

## Cost

Measured on real transcripts, not estimated: **$0.16–0.23 per session that yields
items**, roughly $1–2 a night.

- `maxBudgetUsd` caps a single `claude -p`.
- `maxSpendUsd7d` is a rolling ceiling over `spend.jsonl`, checked in preflight.
- `minTurns` drops short sessions in bash, before any call.

A separate cheap triage model was tried and removed: it cost ~$0.05/session while
every call re-pays ~19k tokens of cached harness context, so splitting the work
bought a cheap gate with an expensive round trip. One call per session now returns
`items: []` when there's nothing worth keeping, which is the same verdict for free.

On a subscription, `claude -p` draws from the same quota as interactive work.
Watch `chezdistill --status` for the first week.

## Offline

Not an error. If the vault is present but the network is down, the work is done
and committed locally, and the next run pushes it. `git pull --rebase` handles the
backlog. Git runs with prompts disabled and a 10-second SSH connect timeout — a
headless job has no terminal to answer a credential prompt, and would otherwise
hang until the machine was rebooted. The state repo has no remote and so is never
affected.

## Troubleshooting

```sh
chezdistill --status                       # paths, MAIN vs cap, spend, last run
chezdistill -n --since 7d                  # what would be read, no API calls
tail -50 ~/.local/state/chezdistill/logs/nightly.log
launchctl print gui/$(id -u)/no.mlz.chezdistill.nightly
launchctl kickstart -k gui/$(id -u)/no.mlz.chezdistill.nightly
```

| Symptom | Cause |
|---|---|
| "cursor held at …" | An extract could not be written. The window is deliberately re-read next run, because the model calls behind it were already paid for. |
| "cannot write to …/30-Claude" at 01:00 but not by hand | macOS privacy protection. See below — the POSIX bits are fine, the syscall is refused. |
| "vault not found" / "has no .obsidian" | The vault isn't cloned or mounted here. The reports are skipped; `MAIN.md` still rendered. |
| "30-Claude does not exist" | Create it in Obsidian. The job will not. |
| Claude isn't loading any rules | Check `~/.config/claude/memory/MAIN.md` exists and that the persona imports it — `grep memory/MAIN.md ~/.config/claude/CLAUDE.md`. |
| Runs but never reaches MAIN | The promotion gate: entries need a second sighting. Check `Candidates.md`. |
| Ran at 09:00, not 01:00 | The Mac was asleep. launchd fired on wake; the cursor means nothing was lost. |
| "7-day spend has reached the ceiling" | Raise `maxSpendUsd7d`, or find out what got expensive in `spend.jsonl`. |
| Agent not in `launchctl list` | Hook 06 didn't run. `chezapply`, then check its output. |
| Did it run at all last night? | `Runs.md` in the vault. |
| It ran but distilled nothing | `## Last run in detail` in `Runs.md` gives the per-session reason. |
| `--undo` says there is no state repo | Nothing has run yet. The first run creates it. |

## Backing it up, and moving to a new Mac

Three repos between them hold everything a replacement Mac needs:

| Repo | Gives you |
|---|---|
| this dotfiles repo | the persona, `settings.json`, the skills, the distiller itself, the plists |
| TheArchive | the `Daily/`, `Weekly/` and `Runs.md` reports |
| a private repo for `~/.local/state/chezdistill` | **the memory** — the extract corpus and `Pinned.md` |

The third is optional and has no remote by default, which means the corpus lives
on exactly one Mac. To back it up, create a private repo and point the state dir
at it:

```sh
gh repo create claude-memory --private
git -C ~/.local/state/chezdistill remote add origin git@github.com:<you>/claude-memory.git
git -C ~/.local/state/chezdistill push -u origin main
```

Every run pushes it from then on, and `chezdistill --status` says so — it warns
`no remote — this Mac is the only copy` until you do.

`logs/`, `cursor.json`, `main-diff-*.txt` and `*.tmp` are gitignored: the cursor
answers "how far has *this* machine read", which is meaningless anywhere else.
The ignore list is re-applied on every run rather than written once, and anything
it newly covers is untracked — a rule added after the repo exists otherwise never
reaches it, and the file stays published.

**A note on push authentication.** A global
`url.git@github.com:.pushinsteadof https://github.com/` rewrites every HTTPS push
to SSH, and the SSH key here lives behind 1Password. At 01:00 the Mac is asleep or
locked, so the agent is locked, so the push fails and the backup quietly stops
happening — the opposite of what a backup is for. The state repo therefore pins
its own push URL to whatever it was cloned from, when that is HTTPS and no push
URL is already set; an SSH remote is left exactly as you configured it. Do the
same for the vault by hand if you want its nightly push to survive a locked
agent:

```sh
git -C ~/Documents/TheArchive config remote.origin.pushurl \
    https://github.com/<you>/TheArchive.git
```

On the new Mac: run `install.sh` for the dotfiles, clone TheArchive, clone this
repo into `~/.local/state/chezdistill`, then `chezdistill --render`. That rebuilds
`MAIN.md`, `Topics/` and `Candidates.md` from the corpus for free — they are pure
output and are deliberately not tracked. The cursor starts fresh, so the first
run reads the last 24 hours rather than re-reading everything.

**This assumes one machine at a time.** Two Macs distilling into the same repo
would collide: they would write the same `extracts/<date>.json` from different
transcripts. The machinery that made that safe — per-host extracts, per-host
fingerprints — was removed on purpose. Restoring or replacing is fine; running
both is not.

## macOS and `~/Documents`

A launchd agent has **no access to `~/Documents`** unless it has been granted it,
and the failure does not look like a permission problem: `[ -w ]` returns true
because the POSIX bits are fine, and only the write syscall is refused with
`Operation not permitted`. Run `chezdistill` by hand from a terminal and it works,
because the terminal has been granted access; the same code at 01:00 writes
nothing.

That is why the job probes with a real write rather than trusting `[ -w ]`, and
why a run that could not write is recorded as **failed** rather than `ok`. Before
that, a nightly job whose every write was refused reported `ok, 1 warning(s)`.

To grant it: **System Settings → Privacy & Security → Full Disk Access**, add
`/bin/bash` (the plist's `ProgramArguments[0]`). It is a broad grant — every bash
script on the machine gets the same reach — which is the trade for having the
reports written unattended.

Without it, nothing is lost that matters to Claude: `MAIN.md`, `Topics/` and the
corpus live outside `~/Documents` and are written normally. Only `Daily/`,
`Weekly/` and `Runs.md` wait for a run you start yourself. Each such night is
recorded, and `Runs.md` names them the next time it can be written:

```markdown
- ⚠ 3 run(s) could not write to the vault — reports skipped that night
```

## Configuration

All in [`src/.chezmoidata/distill.toml`](../src/.chezmoidata/distill.toml).

| Key | Default | Effect |
|---|---|---|
| `memoryPath` | `~/.config/claude/memory` | MAIN, Pinned, Topics, Candidates. Created on demand. |
| `statePath` | `~/.local/state/chezdistill` | Ledger, extracts, cursor, spend, runs, logs. |
| `vaultPath`, `folder` | `~/Documents/TheArchive`, `30-Claude` | Where reports go. Never created. |
| `transcriptRoots` | `~/.config/claude/projects` | A list, so a second install can be added. |
| `mainCapBytes` | `6144` | Hard limit on MAIN, enforced before writing. |
| `minHits` | `2` | The promotion gate. |
| `demoteAfterDays` | `21` | Not reinforced this long → demoted to `Topics/`. |
| `minTurns` | `3` | Free pre-filter: shorter sessions never reach the model. |
| `mapModel`, `narrateModel` | `sonnet`, `opus` | Extraction and prose. |
| `maxBudgetUsd`, `maxSpendUsd7d` | `2.0`, `25.0` | Per call, and rolling over 7 days. |
| `extractRetentionDays` | `90` | After this, an extract's `evidence` quote and `cwd` are stripped. The rule itself is kept. |
| `runsShown` | `30` | Rows in the `Runs.md` table. |
| `runRetentionDays` | `90` | How long the run records behind it are kept. |

Change a value, then `chezup` and `chezdistill --render` to see the effect without
spending anything.

## Secrets and retention

An extract item is the **distilled** result, not a transcript: a model-written
rule (≤200 chars) and explanation, plus one short `evidence` quote and the `cwd`
it came from. The quote and the path are the only parts worth an expiry, and
`extractRetentionDays` strips exactly those after 90 days.

It does **not** delete old extracts, and that is deliberate. `hits` and
`first_seen` are derived from the corpus on every render, so deleting a 90-day-old
sighting would drop a long-established rule back under the promotion gate and
evict it from `MAIN.md` — the memory would forget precisely what has been true
longest. Redaction ages out the sensitive half and leaves the rendered memory
byte-identical.

`gitleaks` sweeps the state dir, the memory dir **and** the vault folder before
any commit, and any hit aborts every commit that run would have made. The
extraction rubric forbids reproducing tokens, keys and `.env` values.

## Turning it off

`chezsetup`, untick *claudeDistiller*, `chezup`. That stops future applies from
deploying the agents, but launchd keeps what it already loaded — unload it by hand:

```sh
launchctl bootout gui/$(id -u)/no.mlz.chezdistill.nightly
launchctl bootout gui/$(id -u)/no.mlz.chezdistill.weekly
```

The vault folder, the memory dir and the state dir are yours; nothing removes
them. Drop the `@`-import by removing the module, and the persona stops loading
`MAIN.md`.
