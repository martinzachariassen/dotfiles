# CLAUDE.md

How to work in this repo — a personal, chezmoi-managed macOS (Apple Silicon)
dotfiles setup. Read this before proposing changes; deeper topic guides live in
[`docs/`](docs/README.md).

> General working defaults (git, code style, communication) come from the global
> agent config outside this repo. This file covers what's specific to the dotfiles,
> and its rules win where they overlap.

## Layout — the `src/` split

- Managed content lives under `src/` — chezmoi's source dir, set via `.chezmoiroot`
  (one line: `src`). It renders into `$HOME`.
- Everything at the repo **root** is tooling chezmoi never deploys: `scripts/`
  (`bin/` user-facing verbs, `ci/` shared checks, `lib/` sourced helpers),
  `packages/` (Brewfiles + editor lists), `tests/` (bats), `docs/`, `install.sh`,
  `.github/`.

## chezmoi conventions

- Edit source files under `src/`, **never the rendered copies in `$HOME`** —
  every apply entry point passes `--force`, so it overwrites local drift. Use
  `chezmoi edit ~/.X` to edit a source, or `chezmoi re-add ~/.X` to capture a live
  edit back into source.
- Preserve the attribute prefixes/suffixes — they change how a file deploys:
  `dot_*` (leading `.`), `private_dot_*` (`0600`), `executable_*` (`+x`),
  `remove_*` (deletes a stale target), `symlink_*`, and `.tmpl` (Go templates).
- Apply-time hooks live in `src/.chezmoiscripts/`, named
  `run_[once|onchange]_[before|after]_NN-name.sh.tmpl` (`NN` sets order). Keep hook
  bodies thin; real logic belongs in `scripts/lib/`. Because hooks sit under `src/`,
  `{{ .chezmoi.sourceDir }}` is `…/dotfiles/src` — reach root-level tooling via
  `{{ .chezmoi.workingTree }}` (the git root).
- Feature gating is data-driven: modules in `src/.chezmoidata/modules.toml`,
  packages in `src/.chezmoidata/brew.toml`. Templates gate with
  `{{ if has "theme" .modules }}`.
- **Removal is always manual — an apply never deletes.** `chezmoi apply` only
  *adds/updates* (renders managed files, `brew bundle`, `mise install`). Reconciling a
  machine back to the repo — removing what the repo no longer tracks — is done by two
  confirm-gated verbs you run by hand: `chezmirror` for Homebrew packages, and
  `chezclean` (`features/clean/cli.sh`) for untracked dotfiles. There are no
  hand-maintained deprecation lists and no auto-prune hooks. If a machine drifts, it's
  up to that machine's owner to run the verbs.
- **`chezclean` reconciles both the top level of `$HOME` and `~/.config`.**
  `~/.config` is a normal `dot_config` dir (not `exact_`), so an apply won't prune
  it. `chezclean` is **tool-aware** — config whose owning tool is still installed
  is kept automatically — and `clean.toml` holds all three lists
  (`keepHome`, `keepConfig`, `owners`) so the two scopes can't drift apart.
  Adding a tool means tracking it (`chezmoi add`), adding it to a keep-list, or —
  if its dir name diverges from its command — adding an `owners` alias. Full
  model in [features/clean](features/clean/README.md).
- **Xcode is out-of-band, by design.** `install.sh` installs only the Xcode
  *Command Line Tools* (Homebrew's prerequisite), and the `appleDev` module's
  Brewfile installs only the Swift *tooling*. Xcode.app itself, the selected
  developer dir, the licence, first-launch components and the iOS simulator
  runtime come from the confirm-gated `chezxcode` verb
  (`features/xcode/cli.sh`), because `xcodes install` needs an Apple ID with 2FA
  and ~40 GB — don't move it into an apply hook or a Brewfile. Its read-only
  probes live in `features/xcode/probe.sh` and are shared with `chezdoctor` so the
  two can't disagree; add checks there, not in either caller.
- **`chezdistill` writes to two places, neither of them this repo.** The memory tier
  (`MAIN.md`, `Topics/`, `Candidates.md`) goes to `~/.config/claude/memory`, beside
  the persona that `@`-imports it; the extract corpus, the hand-written `Pinned.md`,
  the cursor, spend and run log go to `~/.local/state/chezdistill`, in a git repo
  that pushes to a private corpus you attach with `chezdistill --remote <url>`, so a
  replacement Mac fetches the corpus instead of starting empty. Keep that split: memory is derived
  and disposable, state is the source of truth and the only thing worth backing up.
  Inside state the split repeats: **only `extracts/` and `Pinned.md` are tracked.**
  `cursor.json`, `spend.jsonl`, `runs.jsonl` and `logs/` are per-machine, append-only
  telemetry — tracking them makes two Macs conflict on every line and silently kills
  the backup. The corpus is sharded per host (`extracts/<date>.<host>.json`) so two
  Macs in the *same* profile can share a remote; across profiles they must not, since
  `hits` counts sightings over the whole corpus — one private repo each. Read the date with
  `distill_extract_date`, never by stripping `.json`, so pre-sharding files still work.
  **No corpus URL belongs in this repo — it is public.** Where a Mac backs up is a
  prompted answer (`corpusRemote`, blank by default, meaning local only). It is a
  SEED: it points a state repo that has no origin and is never consulted again.
  `git remote origin` is the authority thereafter, which is why an already-attached
  Mac needs no answer and nothing has to write back into a generated chezmoi config.
  A seed disagreeing with origin is surfaced by `--status`, never silently obeyed.
  Blank is a permanent legitimate answer, so persist it like `signingKey` — never
  omit-when-empty like `email`, which re-asks forever by design. Do not reintroduce
  a `[distill.remotes]` table: it shipped two private repo names publicly, handed
  forks a default they cannot use, and could only recognise URLs it already knew —
  a renamed repo walked straight through it.
  **A backup reports what the remote HAS, never what it is called.** Naming an origin
  is not evidence of a push, and treating it as evidence is how two days of rejected
  pushes rendered as `✓ backup`. The verdict is computed once in
  `distill_backup_state` (`HEAD` vs the remote-tracking ref, offline) and only
  *rendered* by `chezdistill --status` and `chezdoctor` — never re-derived in either,
  or the two drift and the weaker one wins. Reconciling is a **merge, never a
  rebase**: a stopped rebase leaves a detached `HEAD` that silently accepts commits
  forever, so a repo found mid-rebase or detached stops before committing rather than
  being repaired by guesswork. Name the branch explicitly in every git call —
  `git init` follows `init.defaultBranch`, which is set here and unset in CI — and
  keep anything written into a *tracked* file normalised, or two Macs spelling one
  remote differently rewrite it against each other every night.
  **A corpus states its own identity, and a URL is not one.** Every corpus carries a
  tracked `corpus.json` — `id` + `profile`, **never a URL or anything derived from
  one** — written once at creation and never rewritten. `profile` is the leak
  boundary and is checked from the *local* copy, so the nightly guard stays offline;
  the remote's copy is read only at attach time. A matching `id` at a different URL
  means the repo moved (adopt it); a different `profile` is a hard stop. A corpus
  with no stamp predates the file: adopt it, stamp it, and say that nothing could
  check it. Joining two corpora is a **data replay, not a history merge** — origin's
  history is the base and this Mac's shards land on top, unioned per shard, which is
  safe only because `hits` counts distinct sessions. Detaching is recorded in the
  state repo's git config so the next run cannot helpfully undo it, and changing a
  remote must clear any `pushurl` pinned to the old one.
  **It has no human-facing output and no vault** — it produced daily and weekly
  notes in Obsidian once, and that half was removed deliberately. The boundary is
  a *written* destination: no generated notes, no digest, no file anyone but
  Claude reads. Asking it questions from a terminal is fine and is how you read
  what it knows — `chezdistill --status`, `--stats`, `--runs`, `--logs`, plus
  `MAIN.md` and `Topics/`. All of those are read-only, make no API calls and
  write nothing. The one concession to having no output is a
  `chezdistill` section in `chezdoctor` — passive liveness only, read-only, no API
  calls. Both directories are ordinary local ones and are simply created.
  Its guiding rule is *the model extracts, bash decides and writes*: every
  judgement (hit counts, what enters `MAIN.md`, what is demoted) is computed in
  `scripts/lib/distill.sh`, and every `claude -p` call runs `--tools ""` with no
  write access. `hits` is **derived** from the extract corpus, never incremented —
  that is what makes `--render`, `--since 7d` and a repeated nightly run idempotent.
  Don't move a decision into a prompt, and don't make `--undo` revert the rendered
  files: `MAIN.md` is derived, so undo reverts the corpus and re-renders. Full guide
  in [docs/distill.md](docs/distill.md).
- **storecode is the work-only exception.** It's installed by its own hook
  (`run_onchange_after_05-storecode`, work profile only) via an installer set in
  `src/.chezmoidata/storecode.toml` — **never** a Brewfile package — and
  `~/.storecode` is permanently on `cleanup.keepHome`. Don't add it to a Brewfile
  or offer it for cleanup.

## Making a change

1. Edit the source under `src/` (or the root tooling).
2. Preview the render: `chezmoi apply --dry-run`, or the CI helper
   `PROFILE=personal MODULES=macApps,theme,jvmStack bash scripts/ci/render-check.sh "$PWD"`.
3. Run the quality gates below.
4. Open a PR.

Day-to-day apply/drift runs through **`chez <verb>`** (`chez up`, `chez apply`,
`chez status`, `chez doctor`, …) — see [`docs/commands.md`](docs/commands.md).
Every verb is one row in [`core/verbs.sh`](core/verbs.sh), which
[`core/chez.sh`](core/chez.sh) reads to dispatch, to render `chez help` and to
feed the zsh completion; adding a verb means adding that row, nothing else. The
old `chezup`-style names remain as aliases. An apply never uninstalls packages.

## Shell & runtimes

- Shell config is plain zsh, XDG layout (`ZDOTDIR=~/.config/zsh`) — no
  oh-my-zsh/prezto/zinit, and no language-runtime managers in shell config.
- **mise owns language runtimes** (`~/.config/mise/config.toml`); **Homebrew owns
  global CLIs and apps** (`features/brew/Brewfile*`). Don't reach for `npm -g` /
  `pip --user` — add the tool to a Brewfile or mise instead.
- Guard shell integrations so a fresh machine starts cleanly before every package
  is installed.

## Git & PRs

- **Always open a PR; never push directly to `main`** — CI must get a chance to
  run. This overrides the general "act and commit" autonomy from the global config.
- Conventional Commits for every commit *and* PR title
  (`<type>(<scope>): <subject>`, ≤ 72 chars) — full format lives in the global
  agent config. Fill in the [PR template](.github/pull_request_template.md).

## Quality gates

CI (`.github/workflows/ci.yml`) and the pre-commit hooks (`.pre-commit-config.yaml`)
run the **same** checks — pass them locally before pushing:

```sh
pre-commit run --all-files             # shellcheck, shfmt, typos, gitleaks, actionlint, zizmor, lint-config, commit-msg
bats tests/                            # shell behavior
bash scripts/ci/lint-config.sh "$PWD"  # every JSON/JSONC/TOML output parses
```

- Shell: `shellcheck --severity=error`, `shfmt -i 4 -ci`, `bash -n` / `zsh -n`.
- Render: `chezmoi apply --dry-run` across the profile/module matrix.
- Workflows: `actionlint` + `zizmor`. Spelling: `typos`.
- **Never commit secrets** — tokens, keys, credentials, signing material. Use
  placeholders or a secret-manager reference; `gitleaks` scans every push.

## Code style

- Bash: `shfmt -i 4 -ci` formatting, `shellcheck`-clean at `--severity=error`.
  Prefer idempotent, detect-then-act logic so re-runs are cheap.
- Keep comments minimal and explain *why, not what*; match each file's existing
  conventions.
