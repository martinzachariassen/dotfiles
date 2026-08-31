# CLAUDE.md

How to work in this repo — a personal, chezmoi-managed macOS (Apple Silicon)
dotfiles setup. Read this before proposing changes.

> General working defaults (git, code style, communication) come from the global
> agent config outside this repo. This file covers what's specific to the
> dotfiles, and its rules win where they overlap.

## Where things are

Two halves, and the boundary is what chezmoi deploys:

- **`src/`** is chezmoi's source dir (set by `.chezmoiroot`). It renders into
  `$HOME`. Nothing outside it is ever deployed.
- **`features/<name>/`** is one directory per thing this repo *does* — its code,
  its bats tests and its prose, together. `core/` holds what no single feature
  owns. `tests/` keeps only the suites that span features. Everything else at
  the root (`scripts/ci/`, `docs/`, `install.sh`, `.github/`) is tooling.

**Start at the feature.** Each has a README that is the single home for its
prose — [brew](features/brew/README.md), [clean](features/clean/README.md),
[distill](features/distill/README.md), [doctor](features/doctor/README.md), and
the rest. The contract for the directory itself is
[`features/README.md`](features/README.md); the reasoning behind the shape is
[`docs/architecture.md`](docs/architecture.md).

## The registry

Two files describe the whole surface and everything else reads them:

- [`core/verbs.sh`](core/verbs.sh) — every verb: its feature, the script it runs,
  its group in `chez help`, its module gate, its summary.
  [`core/chez.sh`](core/chez.sh) reads it to dispatch, to render the help and to
  feed the zsh completion. **Adding a verb is adding a row**, nothing else.
- `features/<name>/feature.sh` — what a feature *is*. Data only, sourced in a
  subshell. `FEATURE_DOCTOR_ORDER` places its `doctor.sh` fragment in
  `chez doctor`'s running order.

Day to day: **`chez <verb>`** — `chez up`, `chez doctor`, `chez cd`. The old
`chez up`-style names remain as aliases. `chez help` is generated, so it cannot
fall behind. See [`docs/commands.md`](docs/commands.md).

## chezmoi conventions

- Edit source files under `src/`, **never the rendered copies in `$HOME`** —
  every apply entry point passes `--force`, so it overwrites local drift. Use
  `chezmoi edit ~/.X`, or `chezmoi re-add ~/.X` to capture a live edit back.
- Preserve the attribute prefixes/suffixes — they change how a file deploys:
  `dot_*` (leading `.`), `private_dot_*` (`0600`), `executable_*` (`+x`),
  `remove_*` (deletes a stale target), `symlink_*`, and `.tmpl` (Go templates).
- Apply-time hooks live in `src/.chezmoiscripts/`, named
  `run_[once|onchange]_[before|after]_NN-name.sh.tmpl` (`NN` sets order). **Keep
  the body in the feature and the guards in the template**: the template resolves
  only what a render can know (the OS, the profile, module gates) and execs
  `features/<n>/hook.sh`. Because hooks sit under `src/`,
  `{{ .chezmoi.sourceDir }}` is `…/dotfiles/src` — reach root-level tooling via
  `{{ .chezmoi.workingTree }}` (the git root).
- **A `run_onchange_` hook must hash every file it delegates to.** Move the body
  out and the template stops changing, so chezmoi keeps matching the recorded
  hash and the hook silently never fires again — no error, no output.
  `tests/chezmoi-scripts.bats` enforces it.
- Feature gating is data-driven: modules in `src/.chezmoidata/modules.toml`,
  packages in `src/.chezmoidata/brew.toml`. Templates gate with
  `{{ if has "theme" .modules }}`. `.chezmoidata/` stays under `src/` because
  chezmoi requires it there; a feature's data file is named after the feature.

## The invariants

Each of these has a fuller explanation in its feature's README. What is here is
the part that must not be broken by accident.

- **An apply never deletes.** `chezmoi apply` only adds and updates. Reconciling
  a machine back to the repo is two confirm-gated verbs you run by hand:
  `chez mirror` for Homebrew packages, `chez clean` for untracked dotfiles. No
  deprecation lists, no auto-prune hooks. → [clean](features/clean/README.md),
  [brew](features/brew/README.md)
- **Xcode is out-of-band, by design.** `install.sh` installs only the Command
  Line Tools; the `appleDev` Brewfile installs only the Swift *tooling*. Xcode
  itself comes from `chez xcode`, because `xcodes install` needs an Apple ID with
  2FA and ~40 GB. Don't move it into an apply hook or a Brewfile. Read-only
  probes live in `features/xcode/probe.sh` and are shared with `chez doctor`, so
  add checks there rather than in either caller. →
  [xcode](features/xcode/README.md)
- **storecode is the work-only exception.** Installed by its own hook from an
  installer set in data — never a Brewfile — and `~/.storecode` is permanently on
  `keepHome`. → [storecode](features/storecode/README.md)
- **chezdistill writes to two places, neither of them this repo,** and has no
  human-facing output by design. Its guiding rule is *the model extracts, bash
  decides and writes*: every judgement is computed in `features/distill/lib/`,
  and every `claude -p` call runs `--tools ""` with no write access. `hits` is
  **derived** from the corpus, never incremented, which is what makes a repeated
  run idempotent. **No corpus URL belongs in this repo — it is public.** →
  [distill](features/distill/README.md), [docs/distill.md](docs/distill.md)
- **`chez doctor` is read-only and its checks live with their features.** A
  section is a sourced fragment defining `doctor_<name>()`; the engines it reads
  through are hard dependencies, because a check that degrades to a green pass is
  worse than no check. → [doctor](features/doctor/README.md)

## Making a change

1. Edit the feature (or `src/`, or the root tooling).
2. Preview the render: `chezmoi apply --dry-run`, or
   `PROFILE=personal MODULES=macApps,theme,jvmStack bash scripts/ci/render-check.sh "$PWD"`.
3. Run the quality gates below.
4. Open a PR.

Adding a whole feature: `cp -r features/_template features/<name>`, fill in the
manifest and README, add a row to `core/verbs.sh` if it has a verb, write
`doctor.sh` if it has checks. `tests/registry.bats` will tell you what you
missed.

## Shell & runtimes

- Shell config is plain zsh, XDG layout (`ZDOTDIR=~/.config/zsh`) — no
  oh-my-zsh/prezto/zinit, and no language-runtime managers in shell config.
- **mise owns language runtimes**; **Homebrew owns global CLIs and apps**
  (`features/brew/Brewfile*`). Don't reach for `npm -g` / `pip --user` — add the
  tool to a Brewfile or to mise instead.
- Guard shell integrations so a fresh machine starts cleanly before every package
  is installed.

## Git & PRs

- **Always open a PR; never push directly to `main`** — CI must get a chance to
  run. This overrides the general "act and commit" autonomy from the global
  config.
- Conventional Commits for every commit *and* PR title
  (`<type>(<scope>): <subject>`, ≤ 72 chars). Fill in the
  [PR template](.github/pull_request_template.md).

## Quality gates

CI (`.github/workflows/ci.yml`) and the pre-commit hooks
(`.pre-commit-config.yaml`) run the **same** checks — pass them locally first:

```sh
pre-commit run --all-files             # shellcheck, shfmt, typos, gitleaks, actionlint, zizmor, lint-config, commit-msg
bats -r tests/ features/               # shell behavior — feature suites included
bash scripts/ci/lint-config.sh "$PWD"  # every JSON/JSONC/TOML output parses
```

- Shell: `shellcheck --severity=error`, `shfmt -i 4 -ci`, `bash -n` / `zsh -n`.
  The file list comes from `git ls-files`, so a moved script cannot drop out.
- Render: `chezmoi apply --dry-run` across the profile/module matrix.
- Workflows: `actionlint` + `zizmor`. Spelling: `typos`.
- **Never commit secrets** — tokens, keys, credentials, signing material. Use
  placeholders or a secret-manager reference; `gitleaks` scans every push.

## Code style

- Bash: `shfmt -i 4 -ci`, `shellcheck`-clean at `--severity=error`. Prefer
  idempotent, detect-then-act logic so re-runs are cheap.
- Keep comments minimal and explain *why, not what*; match each file's existing
  conventions.
- **In a bats test, a bare `[[ ]]` needs `|| return 1`.** bats detects failures
  with an ERR trap that never fires for the `[[ ]]` keyword on bash 3.2, so an
  ungated one passes locally whatever it contains. `tests/bats-assertions.bats`
  enforces it; `docs/development.md` explains it.
