# Health check

`chez doctor` is the read-only report: what this Mac should look like, what it
actually looks like, and the one command that closes each gap. It changes
nothing, ever — that is the whole contract, and it is why it is safe to run when
you have no idea what is wrong.

## Verbs

- `chez doctor` — Read-only health check (repo, brew, auth, mise, shell).

## This directory is the runner, not the checks

[`cli.sh`](cli.sh) owns three things: the tallies, the running order, and the
summary. Every check lives with the feature it belongs to, as
`features/<name>/doctor.sh` — a **sourced fragment** defining one
`doctor_<name>()` function and nothing else.

Sourced, not executed, and that is load-bearing: a fragment calls `pass`, `warn`,
`note` and `fail` directly, so the four counters stay in one process. Running
them as subprocesses would mean parsing exit codes back out of fifteen children
to rebuild the same four numbers, and any check that printed would still print
while the summary silently under-counted.

The checks that belong to no feature live here in [`checks/`](checks) — the
source repo, chezmoi itself, the XDG layout, fonts, and the privacy list macOS
will not let a script read. They carry their order in the filename.

## Order is a number

`FEATURE_DOCTOR_ORDER` in each `feature.sh` places that feature's section;
`checks/NN-*.sh` carry theirs in the filename, on the same numeric scale, and
the runner merges the two. Never directory order — sorted by name the report
would open with auth, brew, claude, containers, which is nobody's idea of a
health check. The order it does use is deliberate:

| | |
|---|---|
| 5–25 | Is there a repo, is chezmoi sane, is the layout right |
| 40–50 | Who you are: Claude config, commit author, signing |
| 60–80 | What is installed: brew, VS Code, runtimes |
| 90–110 | Optional and module-gated: Xcode, distill, containers |
| 120–140 | Informational: cloud auth, fonts, privacy |

Leave gaps. A feature with no checks leaves `FEATURE_DOCTOR_ORDER` empty, and
`features/doctor/tests/doctor.bats` holds the two halves together: an order
without a fragment, or a fragment without an order, both fail.

## Module gating

A gated section is absent, not empty — `feature_active` reads the same
`FEATURE_MODULE` the dispatcher gates verbs with, so `chez help` and
`chez doctor` cannot disagree about which features this Mac has.

## Engines are hard dependencies

The report reads through the same libraries the apply path uses — the Brewfile
tier resolver, the VS Code manifest differ, the Xcode probes — so the report and
the apply cannot disagree about what "tracked" or "ready" means.

Those are sourced unconditionally, and a missing one is a fatal error naming the
file. They used to be `if [ -r … ]` guards, which turn a moved file into
silence: `features/brew/lib/tiers.sh` was renamed out from under a stale path
and the Homebrew section spent a release reporting "could not resolve active
Brewfiles" — and then a green "no untracked brew packages" computed from an
empty set. A degraded check that reports success is worse than no check.

## Exit code

`1` if anything failed, `0` otherwise. Warnings and notes never fail the run:
being signed out of a cloud CLI is a choice, and a report that exits non-zero
for a choice stops being something you run.
