# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal macOS (Apple Silicon) dotfiles managed by [chezmoi](https://chezmoi.io).
The source of truth lives here at `~/Developer/personal/dotfiles` (not the
default `~/.local/share/chezmoi` — set via `sourceDir` in `.chezmoi.toml.tmpl`).
`chezmoi apply` renders templated source files into `$HOME` and runs the hook
scripts in `.chezmoiscripts/`.

**Edit source files here, never the rendered copies in `$HOME`.** A managed file
in `$HOME` is overwritten on the next apply (`apply.force = true`). To capture a
local edit back into source, use `chezmoi re-add ~/.X`.

## Hard rules (CI enforces these — see `.github/workflows/ci.yml`)

- **Conventional Commits** for every commit and PR title (`feat`, `fix`, `docs`,
  `refactor`, `test`, `chore`, `perf`, `build`, `ci`, `style`); subject ≤ 72 chars.
- **Plain zsh only.** Do not introduce oh-my-zsh, prezto, zinit, or a language
  runtime manager into the shell — language runtimes are mise's job.
- Guard shell integrations so a fresh machine starts cleanly before every package
  is installed (tools may not exist yet on first shell launch).
- Never commit secrets, tokens, private keys, credentials, signing material, or
  real `.env` values.

## chezmoi naming conventions (the prefix *is* the behavior)

- `dot_foo` → `~/.foo`; `private_dot_foo` → `~/.foo` with 0600 perms.
- `remove_foo` → chezmoi deletes `~/.foo` (used to retire old dotfiles).
- `*.tmpl` → rendered as a Go template with access to `.chezmoi.*` and the
  `[data]` model (`.profile`, `.email`, `.features.macApps`, `.useOnePassword`, …).
  Use `dig "key" default .` for data that may be absent on machines that haven't
  re-run `chezmoi init`.
- `.chezmoiignore` lists source paths that are **not** deployed to `$HOME` (this
  repo's tooling: `scripts/`, `tests/`, `brewfiles/`, `Brewfile`, `README.md`,
  `CLAUDE.md`, all `AGENTS.md`, etc.).

## Architecture

**Package tiers (`Brewfile` + `brewfiles/`).** The root `Brewfile` is the core
tier (always installed). Optional layers are composed on top based on the install
wizard's answers: `brewfiles/Brewfile.mac-apps` (GUI/AI apps, gated by the
`features.macApps` toggle) and the profile-specific `Brewfile.personal` /
`Brewfile.work`. The `02-brew-bundle` hook + `scripts/lib/brew-bundle.sh` decide
which modules apply.

**Apply lifecycle (`.chezmoiscripts/run_*.sh.tmpl`).** These are the only
chezmoi-managed *commands* (everything else is managed files). Ordering and
re-run behavior come from the filename prefix:
- `run_before_NN-…` / `run_after_NN-…` — every apply, before/after file actions.
- `run_once_before_NN-…` — first apply only.
- `run_onchange_after_NN-…` — only when the rendered script body changes.

The two-digit `NN` orders within a bucket (`02` → `02b` → `03` → `99`); insert
`02a`/`02b` rather than renumbering. Pick `run_after_*` for anything that
**converges installed state** (brew, mise, plugins) so it reconciles on every
run; pick `run_onchange_after_*` for state mutated from a static manifest where
re-running on unchanged input is just noise (vscode extensions, macOS defaults).

Every hook must: use `#!/usr/bin/env bash` + `set -euo pipefail` (or `-uo` to
continue past failing items); include the darwin guard near the top
(`{{ if ne .chezmoi.os "darwin" -}} … exit 0 {{ end -}}`) unless truly
OS-agnostic; and `exec </dev/tty` before any `sudo`/`read` (chezmoi runs scripts
with stdin closed), degrading gracefully with no TTY.

**Engine code (`scripts/lib/`).** Hooks are thin drivers; the real logic lives in
plain, shellcheckable, testable bash under `scripts/lib/` (e.g. `brew-bundle.sh`,
`obsidian-apply.sh`, `ui.sh`, `semver.sh`). A hook does render-time config, then
sources its lib, then calls the entry point. `02-brew-bundle.sh.tmpl` and
`02d-obsidian-apply` are the reference shape.

**User-facing commands (`scripts/`).** `chezup.sh` (pull + apply + converge),
`doctor.sh` (`chezdoctor` health check), `dotfiles-config.sh` (profile/feature
management), `bootstrap-auth.sh` (1Password/git-signing setup), `macos-defaults.sh`.
The `install.sh` at the repo root is the one-shot fresh-Mac bootstrap wizard.

**Runtimes are mise, not Homebrew.** Java/Node/Python come from mise: global
defaults in `~/.config/mise/config.toml` (source: `dot_config/mise/`), per-project
pins in each project's `mise.toml`. Don't add language runtimes to Homebrew.

## Development commands

Run from the repo root. CI mirrors all of these.

```sh
# Shell unit tests (bats) — run the whole suite, or a single file:
bats tests/
bats tests/semver.bats

# Lint + format-check plain shell scripts (NOT the .tmpl hooks — Go directives
# break shellcheck). shfmt enforces `-i 4 -ci`; run `shfmt -w -i 4 -ci <files>`
# to auto-fix. bash -n / zsh -n parse only their FIRST arg, so loop per file:
shellcheck --severity=error --shell=bash install.sh scripts/*.sh scripts/lib/*.sh
shfmt -d -i 4 -ci install.sh scripts/*.sh scripts/lib/*.sh
for f in install.sh scripts/*.sh scripts/lib/*.sh; do bash -n "$f"; done
for f in dot_zshenv dot_config/zsh/dot_zprofile; do zsh -n "$f"; done

# Local commit gates mirroring CI (shellcheck, shfmt, typos, commit message).
# Activate once per clone; run across everything on demand:
pre-commit install --install-hooks
pre-commit run --all-files

# Render every template via dry-run apply (catches Go-template/data errors).
# Vary the env to exercise the matrix of profiles/features:
PROFILE=personal MAC_APPS=true USE_ONE_PASSWORD=true bash scripts/render-check.sh "$PWD"

# Validate all JSON/JSONC/TOML outputs parse:
bash scripts/lint-config.sh "$PWD"

# Resolve every Brewfile formula/cask name without installing (macOS):
bash scripts/brew-resolve.sh "$PWD"
```

Apply / inspect locally: `chez` (apply only), `chezup` (pull + apply + converge),
`chezdoctor` (read-only health check).

The Linux CI render job short-circuits the darwin-guarded hooks to `exit 0`, so
it never exercises the real macOS script bodies — the weekly `render-macos`
canary does. When you touch a macOS-only hook, run `render-check.sh` knowing the
local macOS path is what actually executes those bodies.

## When you add a hook script

Pick the bucket + number and confirm it sorts where you expect; add the darwin
guard (or add it to the exempt set in `tests/chezmoi-scripts.bats`); re-run
`bats tests/chezmoi-scripts.bats`; and add a `tests/<name>.bats` for any new pure
helper logic. `tests/chezmoi-scripts.bats` statically enforces the shebang/strict-
mode/guard rules and dynamically renders + runs every hook on Linux to confirm
the guard fires before any macOS-only command.
