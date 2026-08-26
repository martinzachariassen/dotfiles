# The nightly distiller

`chezdistill` reads the Claude Code transcripts this Mac wrote and renders a
size-capped `MAIN.md` that every future Claude session loads. What you and Claude
worked out yesterday is in context tomorrow.

It is the one verb that talks to a paid API on a timer. That fact shapes the
rules below.

Gated on the `claudeDistiller` module. Verb reference in
[commands.md](commands.md); the persona it feeds is in [ai.md](ai.md).

## Two destinations

| Where | What | Git |
|---|---|---|
| `~/.config/claude/memory/` | `MAIN.md`, `Topics/`, `Candidates.md` | none — rendered from state |
| `~/.local/state/chezdistill/` | the extract corpus and `Pinned.md` — plus cursor, spend, run log and logs, which are gitignored | a local repo, pushed to the profile's private corpus |

Three consequences worth knowing before changing anything:

**The extracts are the memory.** Every rule, hit count and date is derived from
them on each render, so they are what a replacement Mac actually needs. They are
in a local repo so `--undo` works, and that repo pushes to a private remote
chosen by the machine's profile.

**Everything under `memory/` is derived and disposable.** Delete it and
`chezdistill --render` puts it back, for free. Never edit it — the next run
overwrites it. The one exception is `Pinned.md`, which is hand-written and
therefore lives in state, with the other inputs.

**There is no human-facing output.** The audience is Claude. This job wrote
daily and weekly notes into an Obsidian vault once; that half was removed
deliberately, and reintroducing a reporting destination is a design change, not
a feature. To see what it knows, read `MAIN.md`, a note in `Topics/`, or
`chezdistill --status`.

## Turning it on

One command, from a checkout of this repo:

```sh
bash ~/Developer/personal/dotfiles/scripts/bin/distill.sh --setup
```

It goes through the full path — add `claudeDistiller` to the module list, apply,
register the launchd agent, seed a `MAIN.md` so the persona's `@`-import resolves
from the first session rather than after the first successful night, then print
`--status`. Every step is confirmed and every step is idempotent, so re-running
it on a machine that is already set up just reports green. It makes no API calls.

The long form of the script path is not an accident: the `chezdistill` shell verb
is gated on the module, so until `--setup` has turned the module on, the verb does
not exist. Afterwards, `chezdistill --setup` works normally.

The memory dir and the state dir are ordinary local directories with no mount to
be wrong about, so they are simply created.

### Doing it by hand

1. **Enable the module**: `chezsetup`, tick *claudeDistiller*. It's in the base
   profile, so new machines get it by default. A machine set up *before* the
   module existed is offered it once by `chezup` itself — see
   [the new-module gate](commands.md#new-modules-since-this-mac-was-set-up);
   answer `y` there and this step is done.
2. **Apply**: `chezup`. Hook 06 registers the launchd agent.
3. **Check**: `chezdistill --status`.

## Running it now

Nothing has to wait for 01:00 — the flags below are the same code path launchd
takes, just started by hand:

```sh
chezdistill              # the nightly job, right now
chezdistill -n           # preview: what it would read and run, no model calls
chezdistill --since 7d   # backfill the last week
chezdistill --render     # rebuild the memory tier from the corpus, free
chezdistill --status     # where things live, MAIN size vs cap, spend, last run
chezdistill --undo       # revert the last state commit and re-render
```

`-n` first is the cheap habit: it prints the sessions that would be read and the
calls that would be made without spending anything. A session already read is
skipped by the cursor, so running the job by hand does not double-bill you for
the night.

## What happens each night

```
01:00  launchd fires
  │
  ├─ PREFLIGHT   memory + state paths writable? under the spend ceiling?
  ├─ CURSOR      read cursor.json, else 24h ago
  ├─ HARVEST     transcripts touched since, subagent files excluded
  ├─ FILTER      keep typed human turns + assistant prose; drop tool traffic,
  │                thinking, sidechains, harness noise        ~16x smaller
  ├─ GATE        fewer than minTurns typed turns → skipped, free, no API call
  ├─ BRAKE       spend ceiling re-checked per session → stop reading, hold cursor
  ├─ MAP         one model call per surviving session → items as JSON
  │                → state/extracts/<date>.<host>.json — a failed write here holds
  │                  the cursor back: calls are billed, no re-run recovers them
  ├─ RENDER      bash builds MAIN.md, Topics/, Candidates.md
  ├─ PRUNE       age out evidence quotes past extractRetentionDays
  ├─ RECORD      append the run to state/runs.jsonl
  ├─ GITLEAKS    over state and memory → abort on any hit
  └─ COMMIT      the state repo, locally; then pushed to the profile's corpus
```

Every step from RECORD down runs whether the run succeeded or failed — a failure
that leaves no trace is a failure you find out about weeks later. A run that
harvested nothing still records, so "nothing ran last night" and "nothing was
worth keeping last night" stay distinguishable.

**The model extracts; bash decides and writes.** Every judgement — hit counts,
what enters MAIN, what gets demoted — is computed in
[`scripts/lib/distill.sh`](../scripts/lib/distill.sh). No model call has write
access: each runs `--tools ""`, takes its payload on stdin, returns
schema-validated JSON. Keeping the decisions in bash is what makes a re-run of an
already-distilled day produce a byte-identical file and therefore no commit.

## The rubric — where the behaviour actually lives

Everything the job *decides* is bash. What it *captures* comes from one prompt,
and that prompt is an ordinary Markdown file you can edit:
[`skills/distill/SKILL.md`](../src/dot_config/claude/skills/distill/SKILL.md) —
the item kinds, what counts, what never counts, how long a rule may be.

It is deployed to `~/.config/claude/skills/distill/SKILL.md` by an apply, and
doubles as an interactive slash command: `/distill` on a live conversation runs
the same rubric by hand.

**The job reads it as a file, not as a skill.** Every model call runs with
`--tools ""`, which removes the Skill tool along with everything else, so the body
is `cat`-ed into `--system-prompt-file`. That flag *replaces* the default system
prompt rather than appending to it, which is where the roughly tenfold cost drop
came from: no persona, no tool guidance, just the rubric.

### Editing it

Edit the source under `src/`, `chezapply`, and the next run picks it up. To see
the effect you have to pay for a run — rendering is free, extraction is not.

Two things that look like prompt problems and are not:

- **A length limit belongs in the JSON schema, not the prompt.** Asking for 200
  characters is ignored often enough to matter; `maxLength` is not. That is why
  the rule cap lives in [`distill_schema_map`](../scripts/lib/distill.sh) rather
  than in the rubric.
- **A horizon in the rubric silently filters whole categories.** "Worth knowing a
  month from now" is right for a rule and wrong for an open thread, which matters
  most the day after. Before that carve-out the corpus held 19 gotchas and zero
  open threads — the instruction was working exactly as written.

## Two tiers, priced differently

| Tier | Where | What it costs |
|---|---|---|
| `MAIN.md` | 6 KB cap, `@`-imported by the persona | paid for in **every** session, forever |
| `Topics/*.md` | unbounded, beside MAIN | free — read only when Claude looks a rule up |

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

## What gets written

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

### `Candidates.md`

Everything that hasn't earned a place in MAIN: seen only once, or past the gate
but gone stale. Entries here affect nothing, and nothing is deleted to get here.

### `--status` — did it run, and did it work?

There is no report to open, so this is where a run's outcome shows up:

```text
✓ memory   ~/.config/claude/memory
✓ state    ~/.local/state/chezdistill
✓ MAIN.md  5104B of 6144B
· corpus   87 sighting(s) of 41 entries, oldest 2026-06-02
· waiting  22 entries below the gate or stale — see Candidates.md
✓ backup   58 commit(s), pushed to https://github.com/<you>/claude-memory-personal
· spend    $1.87 of $25 over 7 days
✓ last run 2026-08-24 01:03 UTC · ok · 3/7 session(s) · 170s · $0.42
           a1b2c3d4  12 turn(s) · kept · 5 item(s)
           e5f6a7b8  2 turn(s) · too short, no model call
· cursor   read up to 2026-08-24T01:03:11Z
```

**`3/7` is the number to read**, and the per-session lines under it are why it is
legible: seven sessions seen and none distilled looks like a broken job until you
can see that six were under `minTurns` and one had nothing durable in it — free,
and working as designed.

The records behind it are `runs.jsonl`, kept for `runRetentionDays`.

### `chezdoctor` — is it still alive?

`--status` answers only when you think to ask, and a job with no human-facing
output is a job you stop thinking about. So the health check you already run for
everything else carries a **chezdistill** section: the agent registered with
launchd, how long ago the last run was (a failure fails, more than three days
warns), whether `MAIN.md` exists and how it sits against the cap, and whether the
state repo is backed up — to *its own* profile's corpus. It is read-only and
makes no API calls.

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
| A rule is wrong or badly worded | Write the correct one in `~/.local/state/chezdistill/Pinned.md`. It is prepended into `MAIN.md` verbatim, never demoted, never rewritten. |
| Last night's run made a mess | `chezdistill --undo` reverts the state repo's last commit and re-renders the memory from it. |
| You edited the corpus or `Pinned.md` | `chezdistill --render` rebuilds the memory tier. No API calls. |
| An entry should be gone entirely | Delete its sightings from `extracts/<date>.<host>.json` — every shard of that date, if more than one Mac contributed. Everything about an entry is derived from the corpus, so that is the only place it exists. |

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
slept through; "what has happened since I last read?" cannot.

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
- `maxSpendUsd7d` is a rolling ceiling over `spend.jsonl`, checked in preflight
  **and again before every session**. A nightly run reads two days and cannot
  approach it; `--since 90d` reads hundreds of sessions in one go, and a ceiling
  checked once before all of them is not a ceiling. Hitting it mid-run stops the
  loop rather than failing it: the sessions already extracted are kept, and the
  cursor is held so the ones never reached are read next time.
- `minTurns` drops short sessions in bash, before any call.

A separate cheap triage model was tried and removed: it cost ~$0.05/session while
every call re-pays ~19k tokens of cached harness context, so splitting the work
bought a cheap gate with an expensive round trip. One call per session now returns
`items: []` when there's nothing worth keeping, which is the same verdict for free.

On a subscription, `claude -p` draws from the same quota as interactive work.
Watch `chezdistill --status` for the first week.

## Offline

Not an error. The work is done and committed locally, and the next run pushes it. Git runs with prompts
disabled and a 10-second SSH connect timeout — a headless job has no terminal to
answer a credential prompt, and would otherwise hang until the machine was
rebooted.

## Troubleshooting

```sh
chezdoctor                                 # is the agent registered, did it run
chezdistill --status                       # paths, MAIN vs cap, spend, last run
chezdistill -n --since 7d                  # what would be read, no API calls
tail -50 ~/.local/state/chezdistill/logs/nightly.log
launchctl print gui/$(id -u)/no.mlz.chezdistill.nightly
launchctl kickstart -k gui/$(id -u)/no.mlz.chezdistill.nightly
```

| Symptom | Cause |
|---|---|
| "cursor held at …" | An extract could not be written. The window is deliberately re-read next run, because the model calls behind it were already paid for. |
| Claude isn't loading any rules | Check `~/.config/claude/memory/MAIN.md` exists and that the persona imports it — `grep memory/MAIN.md ~/.config/claude/CLAUDE.md`. |
| Runs but never reaches MAIN | The promotion gate: entries need a second sighting. Check `Candidates.md`. |
| Ran at 09:00, not 01:00 | The Mac was asleep. launchd fired on wake; the cursor means nothing was lost. |
| "7-day spend has reached the ceiling" | Raise `maxSpendUsd7d`, or find out what got expensive in `spend.jsonl`. |
| "spend ceiling reached — stopping after N session(s)" | A backfill hit the ceiling part-way. What it read is saved and the cursor is held; raise the ceiling or wait for the 7-day window to roll, then run again. |
| Agent not in `launchctl list` | Hook 06 didn't run. `chezapply`, then check its output. |
| Did it run at all last night? | `chezdistill --status` — `last run`. |
| It ran but distilled nothing | The per-session lines under `last run` give the reason for each. |
| `--undo` says there is no state repo | Nothing has run yet. The first run creates it. |

## Backing it up, and moving to a new Mac

Two repos between them hold everything a replacement Mac needs:

| Repo | Gives you |
|---|---|
| this dotfiles repo | the persona, `settings.json`, the skill, the distiller itself, the plist |
| a private repo for `~/.local/state/chezdistill` | **the memory** — the extract corpus and `Pinned.md` |

The second one you do not have to set up. The state repo takes its remote from
the machine's profile the first time it is used, so a fresh Mac backs itself up
without anyone remembering a `git remote add`:

| Profile | Remote |
|---|---|
| personal | `claude-memory-personal`, private |
| work | `claude-memory-work`, private |

The table lives in
[`src/.chezmoidata/distill.toml`](../src/.chezmoidata/distill.toml) under
`[distill.remotes]`, keyed by `.profile`. Both repos must exist and be private —
extracts carry short verbatim quotes from your transcripts. Create them once:

```sh
gh repo create claude-memory-personal --private
gh repo create claude-memory-work --private
```

A profile with no entry in the table gets no remote and `chezdistill --status`
warns `no remote — this Mac is the only copy`, which is the old behaviour. A
remote you set by hand — your own mirror, a self-hosted host — is never
overwritten.

**One repo per profile, never one shared.** `hits` is derived by counting
sightings across the whole corpus, so a work Mac and a personal one sharing a
remote does not merely mix the two — it merges them irreversibly, and a rule
learned at work starts being applied to personal sessions.

Which is why the interesting half of the table is not the adopting but the
**refusing**. If `origin` is another profile's repo — a `set-url` typo, a state
dir copied off an old machine — chezdistill stops before it extracts anything:

```
✗ the corpus at ~/.local/state/chezdistill pushes to the personal remote, but this is a work Mac
  nothing will be distilled until that is settled. To adopt this Mac's own corpus:
    git -C ~/.local/state/chezdistill remote set-url origin https://github.com/<you>/claude-memory-work.git
    git -C ~/.local/state/chezdistill remote set-url --push origin https://github.com/<you>/claude-memory-work.git
```

`chezdoctor` and `chezdistill --status` fail on the same condition. Without the
check both of them reported a cheerful `✓ corpus backed up` at it, because it is
backed up — to the wrong place, one push past undoing. URLs are compared as
`host/owner/repo`, so `git@github.com:you/x.git` and `https://github.com/you/X`
are recognised as the same repo and do not trip it.

**Nothing pushes outside a run.** The push is the last step of `distill_run_end`,
after the secret sweep, and it is the same commit that carries the run record —
so a night that failed still lands on the remote with its reason attached. If the
machine is offline the commit is made locally anyway and the next run carries it;
"deferred" in the output is not an error.

The repo writes its own `README.md` on every run — what each path is, why
`cursor.json` and `logs/` are deliberately absent, and the two-command restore.
It is generated, so don't edit it on GitHub; change
`distill_render_state_readme` instead. `Pinned.md` is seeded empty the first time
the repo is created, so the "edit `Pinned.md`" instruction in `MAIN.md` points at
a file that exists.

**Only the corpus and `Pinned.md` are tracked.** `cursor.json`, `spend.jsonl`,
`runs.jsonl`, `logs/` and `*.tmp` are gitignored, for one reason each way: none of
them answers a question about anywhere but *this* machine ("how far have I read",
"what did I bill", "did my 01:00 fire"), and all three files are append-only, so
two Macs pushing to one remote would conflict on every line of them and the
backup that actually matters would stop. Nothing there can be regenerated;
everything ignored can be lived without.

The ignore list is re-applied on every run rather than written once, and anything
it newly covers is untracked — a rule added after the repo exists otherwise never
reaches it, and the file stays published.

**A note on push authentication.** A global
`url.git@github.com:.pushinsteadof https://github.com/` rewrites every HTTPS push
to SSH, and the SSH key here lives behind 1Password. At 01:00 the Mac is asleep or
locked, so the agent is locked, so the push fails and the backup quietly stops
happening — the opposite of what a backup is for. The state repo therefore pins
its own push URL to whatever it was cloned from, when that is HTTPS and no push
URL is already set; an SSH remote is left exactly as you configured it.

On the new Mac: run `install.sh` for the dotfiles, clone this repo into
`~/.local/state/chezdistill`, then `chezdistill --render`. That rebuilds
`MAIN.md`, `Topics/` and `Candidates.md` from the corpus for free — they are pure
output and are deliberately not tracked. The cursor starts fresh, so the first
run reads the last 24 hours rather than re-reading everything.

### Two Macs on one remote

Within a profile this is safe, and the corpus layout is the reason. Each machine
writes `extracts/<date>.<host>.json` — its own file — so a day both Macs
contributed to is two files that merge without a conflict, and the derivation
groups by entry id across all of them, counting **distinct sessions**. A rule seen
once on each Mac is a rule with two hits, which is exactly right; a day re-read on
one Mac still counts once, which is also right.

Nothing needs migrating. `distill_extract_date` reads the date off the front of
the filename, so a pre-sharding `extracts/<date>.json` written before this keeps
deriving, ageing and pruning identically alongside the new ones.

What is *not* safe is one remote across profiles, which is why the profile picks
the remote and a foreign one is refused — see the table above.

## Configuration

All in [`src/.chezmoidata/distill.toml`](../src/.chezmoidata/distill.toml).

| Key | Default | Effect |
|---|---|---|
| `memoryPath` | `~/.config/claude/memory` | MAIN, Topics, Candidates. Created on demand. |
| `statePath` | `~/.local/state/chezdistill` | Extracts, Pinned, cursor, spend, runs, logs. |
| `transcriptRoots` | `~/.config/claude/projects` | A list, so a second install can be added. |
| `mainCapBytes` | `6144` | Hard limit on MAIN, enforced before writing. |
| `minHits` | `2` | The promotion gate. |
| `demoteAfterDays` | `21` | Not reinforced this long → demoted to `Topics/`. |
| `minTurns` | `3` | Free pre-filter: shorter sessions never reach the model. |
| `mapModel` | `sonnet` | The one model tier. One call per session. |
| `maxBudgetUsd`, `maxSpendUsd7d` | `2.0`, `25.0` | Per call, and rolling over 7 days. |
| `extractRetentionDays` | `90` | After this, an extract's `evidence` quote and `cwd` are stripped. The rule itself is kept. |
| `runRetentionDays` | `90` | How long run records are kept. |

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

`gitleaks` sweeps the state dir **and** the memory dir before any commit, and any
hit aborts every commit that run would have made. The extraction rubric forbids
reproducing tokens, keys and `.env` values.

## Turning it off

`chezsetup`, untick *claudeDistiller*, `chezup`. That stops future applies from
deploying the agent, but launchd keeps what it already loaded — unload it by hand:

```sh
launchctl bootout gui/$(id -u)/no.mlz.chezdistill.nightly
```

The memory dir and the state dir are yours; nothing removes them. Drop the
`@`-import by removing the module, and the persona stops loading `MAIN.md`.

Unticking it stays unticked: `chezup`'s new-module gate only offers modules this
Mac has *never been asked about*, and the module is recorded as offered whether
you said yes or no.
