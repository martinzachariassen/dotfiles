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
  packages in `src/.chezmoidata/packages.toml`. Templates gate with
  `{{ if has "theme" .modules }}`.
- **Removal is always manual — an apply never deletes.** `chezmoi apply` only
  *adds/updates* (renders managed files, `brew bundle`, `mise install`). Reconciling a
  machine back to the repo — removing what the repo no longer tracks — is done by two
  confirm-gated verbs you run by hand: `chezmirror` for Homebrew packages, and
  `chezclean` (`scripts/bin/clean.sh`) for untracked dotfiles. There are no
  hand-maintained deprecation lists and no auto-prune hooks. If a machine drifts, it's
  up to that machine's owner to run the verbs.
- **`chezclean` reconciles both the top level of `$HOME` and `~/.config`.** `~/.config`
  is a normal `dot_config` dir (not `exact_`), so an apply won't prune it; instead
  `chezclean` surfaces untracked `~/.*` (vs `cleanup.keepHome`) and untracked
  `~/.config/X` (vs `cleanup.keepConfig`) and removes only what you confirm. It's
  **tool-aware**: config whose owning tool is still present is kept automatically — the
  union of three signals: the tool's brew package is installed, its command is on PATH
  (so mise/gcloud tools count), *or* its owning VS Code extension is in
  `code --list-extensions` — matching most tools by a stem heuristic
  (`command -v <name-minus-dot>`) and the `cleanup.owners` map for
  name↔command/package/extension aliases (`.kube`→`kubectl`, `.m2`→`mvn` from mise,
  `.sonarlint`→`sonarsource.sonarlint-vscode`). Adding a tool = track it
  (`chezmoi add`), add it to a keep-list, or (if its dir name diverges from its
  command) add an `owners` alias; `keepConfig`/`keepHome`/`owners` all live in
  `cleanup.toml` so they can't drift. Full model in
  [docs/lifecycle.md](docs/lifecycle.md).
- **Xcode is out-of-band, by design.** `install.sh` installs only the Xcode
  *Command Line Tools* (Homebrew's prerequisite), and the `appleDev` module's
  Brewfile installs only the Swift *tooling*. Xcode.app itself, the selected
  developer dir, the licence, first-launch components and the iOS simulator
  runtime come from the confirm-gated `chezxcode` verb
  (`scripts/bin/xcode.sh`), because `xcodes install` needs an Apple ID with 2FA
  and ~40 GB — don't move it into an apply hook or a Brewfile. Its read-only
  probes live in `scripts/lib/xcode.sh` and are shared with `chezdoctor` so the
  two can't disagree; add checks there, not in either caller.
- **`chezdistill` writes to three places, none of them this repo.** The memory tier
  (`MAIN.md`, `Pinned.md`, `Topics/`, `Candidates.md`) goes to
  `~/.config/claude/memory`, beside the persona that `@`-imports it; the extract
  corpus, `Pinned.md`, cursor, spend and run log to `~/.local/state/chezdistill`, in a git repo
  whose remote is optional (add one and every run pushes, so a replacement Mac
  clones the corpus instead of starting empty); and
  only the reports you read (`Daily/`, `Weekly/`, `Runs.md`) to
  `~/Documents/TheArchive/30-Claude`. Keep that split — putting `Topics/` in the
  vault makes it unreadable to Claude, and putting extracts back in the vault puts
  transcript text on a remote.
  **All three are profile-scoped, and the two corpora are never shared.** A work
  Mac and a personal one answer to different employers, so the profile picks the
  *destinations* rather than filtering content: `[distill.byProfile.work]` in
  `src/.chezmoidata/distill.toml` points work at `~/Documents/WorkArchive`,
  resolved by `distill_merge_profile` as a shallow overlay (the same lookup shape
  as `brewfiles.byProfile`, because `.chezmoidata` can't be templated). Confine
  overrides to the destinations — two profiles differing on `minHits` would be two
  memories built to different standards. `memoryPath`/`statePath` are never
  overridden (a test enforces it): they're already per-machine, and no code ever
  gives the state repo a remote. Adding one is manual and must be **one repo per
  profile** — a shared remote merges the corpora irreversibly, since `hits` is
  derived by counting sightings across the whole corpus.
  **It never creates the vault**: an uncloned one looks exactly like an empty
  directory, so a missing vault means "skip the reports, render the memory, exit 0",
  never "create it". `chezdistill --setup`, the confirm-gated on-switch, may create
  `30-Claude/` and only that, and only once the vault and its `.obsidian` dir are
  already there — don't extend it to the vault, and don't move any of it into
  preflight. Memory and state are ordinary local directories and are simply created.
  Its guiding rule is *the model extracts and narrates, bash decides and writes*:
  every judgement (hit counts, what enters `MAIN.md`, what is demoted) is computed in
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

Day-to-day apply/drift runs through the `chez*` shell verbs (`chezup`, `chezapply`,
`chezstatus`, `chezdoctor`, …) — see [`docs/commands.md`](docs/commands.md). An apply
never uninstalls packages.

## Shell & runtimes

- Shell config is plain zsh, XDG layout (`ZDOTDIR=~/.config/zsh`) — no
  oh-my-zsh/prezto/zinit, and no language-runtime managers in shell config.
- **mise owns language runtimes** (`~/.config/mise/config.toml`); **Homebrew owns
  global CLIs and apps** (`packages/Brewfile*`). Don't reach for `npm -g` /
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
