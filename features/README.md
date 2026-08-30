# `features/` — one directory per feature

A feature is a thing this repo *does*: install packages, converge the machine,
distil Claude sessions, keep Xcode ready. Each one gets a directory, and
everything that belongs to it goes inside — code, tests and its documentation.

The rule for what belongs where is one sentence: **if exactly one feature cares
about it, it lives in that feature.** Everything else is in [`core/`](../core).

Areas with no behaviour get no directory. The shell, the terminal, the theme and
the Claude persona are files under `src/` plus a guide in `docs/`; there is
nothing to co-locate.

## The skeleton

Only `feature.sh` and `README.md` are required. Add the rest as the feature
needs them.

| File | What it is |
|---|---|
| `feature.sh` | The manifest. Data only — see below. |
| `README.md` | The dossier: what this feature is, how to use it, why it works the way it does. The single home for its prose. |
| `cli.sh` | Entry point for its verbs. Receives the verb as `$1`. |
| `lib.sh` or `lib/` | The engine. Split into `lib/` once one file stops being readable. |
| `doctor.sh` | A **sourced fragment** defining `doctor_<name>()`, nothing else. Sourced rather than executed so it can call `pass`/`warn`/`note`/`fail` and keep the tallies in one process. |
| `hook.sh` | The body its `.chezmoiscripts` hook delegates to. |
| `tests/*.bats` | Its tests. Cross-cutting suites stay in the top-level `tests/`. |

## The manifest

```sh
FEATURE_NAME=brew                     # must match the directory name
FEATURE_TITLE="Homebrew packages"     # heading used by chezdoctor
FEATURE_MODULE=""                     # module that gates it; empty = always on
FEATURE_DOCTOR_ORDER="60"             # position in chezdoctor; empty = no checks
```

Three rules, each enforced by `tests/registry.bats`:

- **Data only, no side effects.** It is sourced in a subshell to read one value,
  and may be read many times in a run.
- **`FEATURE_MODULE` must name a real module** from
  `src/.chezmoidata/modules.toml`. It means "this feature does nothing at all
  without that module" — not "some of its files are gated". `claude` deploys its
  settings regardless of `claudePersona`, so its gate is empty.
- **`FEATURE_DOCTOR_ORDER` must be unique**, and ordering is by this number and
  never by directory name. The current section order is deliberate: repo, then
  chezmoi, then identity, then packages, then runtimes, then optional modules,
  then informational. Alphabetical would scramble it. Leave gaps.

Verbs are **not** declared here — they live in [`core/verbs.sh`](../core/verbs.sh),
the single source of truth for the command surface, which names the owning
feature per verb. Declaring them twice is how the two drift apart.

## Adding a feature

1. `cp -r features/_template features/<name>` — or copy the nearest sibling.
2. Fill in the manifest and the README.
3. If it has a verb, add a row to `core/verbs.sh`.
4. If it has checks, write `doctor.sh` and give it an order.

`tests/registry.bats` will tell you what you missed.
