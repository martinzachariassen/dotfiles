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
  `chezmoi apply` overwrites local drift (`apply.force = true`). Use
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
- **HOME is mirrored to the repo.** `~/.config` is an `exact_` dir
  (`src/exact_dot_config/`), so an apply prunes untracked *top-level* `~/.config/X`;
  the keep-list in `src/.chezmoidata/cleanup.toml` (`cleanup.keepConfig`, rendered
  into `.chezmoiignore`) spares auth/state dirs (`op`, `gh`, `gcloud`, `chezmoi`).
  The top level of `$HOME` is reconciled on demand by `chezclean`
  (`scripts/bin/clean.sh`) against `cleanup.keepHome`. `chezclean` is **tool-aware**:
  it keeps config whose owning tool is still present — the union of three signals:
  the tool's brew package is installed, its command is on PATH (so mise/gcloud tools
  count), *or* its owning VS Code extension is in `code --list-extensions` — matching
  most tools by a stem heuristic (`command -v <name-minus-dot>`) and the
  `cleanup.owners` map for name↔command/package/extension aliases (`.kube`→`kubectl`,
  `.m2`→`mvn` from mise, `.sonarlint`→`sonarsource.sonarlint-vscode`). Adding a tool =
  track it (`chezmoi add`), add it to the keep-list, or (if its dir name diverges from
  its command) add an `owners` alias; all three lists live in one file so they can't
  drift. **Extension-owned dirs are also auto-pruned:** the `owners` entries with an
  `extension` field are coupled to the extension lifecycle by
  `run_onchange_after_03b-vscode-home-prune` — it runs after the 03 extension mirror,
  so `code --list-extensions` already matches `packages/vscode-extensions.txt`, then
  `rm -rf`s any extension-owned `$HOME` dir whose extension is no longer installed.
  Drop an extension ID from the manifest → next apply uninstalls it *and* deletes its
  dir, identically on every machine (deleting an extension in the VS Code UI is
  reverted by 03 — remove it from the manifest instead). Full model in
  [docs/lifecycle.md](docs/lifecycle.md).
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

Day-to-day apply/drift runs through the `chez*` shell verbs (`chezup`, `chez`,
`chezdiff`, `chezdoctor`, …) — see [`docs/commands.md`](docs/commands.md). An apply
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
