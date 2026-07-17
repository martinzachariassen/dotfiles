# CLAUDE.md

Guidance for AI assistants and contributors working in this repo — a personal,
chezmoi-managed macOS (Apple Silicon) dotfiles setup. Read this before proposing
changes; deeper topic guides live in [`docs/`](docs/README.md).

> The maintainer's cross-project preferences layer in from a global config
> outside this repo and always yield to the rules here.

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

- **Always open a PR; never push directly to `main`** — CI must get a chance to run.
- [Conventional Commits](https://www.conventionalcommits.org) for every commit
  **and** the PR title: `<type>(<scope>): <subject>`, imperative, ≤ 72 chars.
  Types: `feat, fix, docs, refactor, test, chore, perf, build, ci, style`. Breaking
  changes append `!` and add a `BREAKING CHANGE:` footer.
- PR description = what changed, *why*, and any rollout/follow-up. Follow the
  [PR template](.github/pull_request_template.md).

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
- Keep comments to the necessary minimum and explain **why, not what**.
- Match the surrounding file's conventions over any general preference.
