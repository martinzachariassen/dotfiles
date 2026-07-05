# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal macOS (Apple Silicon) dotfiles managed by [chezmoi](https://chezmoi.io).
The repo lives at `~/Developer/personal/dotfiles` (not the default
`~/.local/share/chezmoi` — set via `sourceDir` in `src/.chezmoi.toml.tmpl`).
`chezmoi apply` renders templated source files into `$HOME` and runs the hook
scripts in `src/.chezmoiscripts/`.

**Repo layout — the `src/` split.** `.chezmoiroot` (one line, `src`) makes `src/`
chezmoi's **source directory**: everything under `src/` is managed content that
deploys to `$HOME` (`dot_config/`, `dot_zshenv`, `private_dot_ssh/`, `Library/`,
plus the `.chezmoi*` machinery). Everything at the **repo root** is tooling
chezmoi never sees: `scripts/` (+ `lib/`), `packages/` (Brewfiles + editor
lists), `tests/`, `docs/`, `install.sh`, `.github/`. So inside a hook,
`{{ .chezmoi.sourceDir }}` is `…/dotfiles/src`; reaching root-level tooling
(`scripts/lib/*`, `packages/Brewfile*`) uses `{{ .chezmoi.workingTree }}` (the
git working tree = repo root). That `.chezmoi.workingTree` idiom is how the
boundary is crossed — grep for it when wiring a hook to a root-level file.

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
  `[data]` model (`.profile`, `.name`, `.email`, `.signingMode`, `.signingKey`,
  `.modules`). Use `dig "key" default .` for data that may be absent on machines
  that haven't re-run `chezmoi init` (e.g. `dig "modules" (list) .`).
- `src/.chezmoiignore` lists source paths that are **not** deployed to `$HOME`.
  Since the repo tooling now lives *outside* the source dir (at the repo root,
  above `src/`), chezmoi can't see it anyway, so this file slimmed to just the
  in-`src/` cases (the Obsidian vault's own `README.md`/`AGENTS.md`, and the
  module-gated personal content).

## Architecture

**Data model + modules (`src/.chezmoi.toml.tmpl` + `src/.chezmoidata/`).** The
setup questions are chezmoi's own `chezmoi init` prompt*Once functions: `profile`
(personal/work/minimal), `signingMode` (1password/ssh-key/off), and a `modules`
multi-select. The chosen module list drives everything — templates gate on it
with `has "X" .modules`, the templated `src/.chezmoiignore` deploys personal
content (Obsidian, CLAUDE.md) only when its module is on, and hooks skip when
theirs is off. The module catalog + per-profile default selection + the
profile→Brewfile map live once in `src/.chezmoidata/{modules,packages}.toml`.

**The wizard front-end (`scripts/wizard.sh`).** chezmoi's `promptChoice`/
`promptMultichoice` render an interactive TUI picker (charmbracelet/`huh`) that
reads `/dev/tty` in raw mode and is unreliable under `curl | bash` and some
terminals — it can fail to register navigation and just confirm the highlighted
default. So the interactive path is a thin plain-text wrapper: `wizard.sh` asks
each question with plain `read` from `/dev/tty` (numbered menus / typed answers /
number-toggle multi-select — all terminal-agnostic), then hands the answers to
chezmoi via its non-interactive flags (`--promptString/-Choice/-Multichoice`,
keyed by each prompt's *message* text, multichoice items joined with `/`). It
stays bash-3.2 compatible (a fresh Mac has only system bash until Homebrew) and
extracts the messages/choices from `src/.chezmoi.toml.tmpl` at runtime so they
never drift (`wizard.sh` reads it via `$ROOT/src/...`). The choice/module prompts
have three degrading tiers, each behind a predicate: `use_gum` → gum's arrow +
space-toggle pickers (re-runs; current selection pre-checked via `--selected`,
labels rendered comma-free because that flag is comma-delimited, mapped back to
keys by exact match; `WIZARD_NO_GUM=1` skips); else `use_tui` → a pure-bash 3.2
arrow/space picker (`_tui_read_key` decodes the ESC[A/B burst; also accepts
digit + j/k so it survives a terminal that eats arrow escapes; `WIZARD_NO_TUI=1`
skips); else the numbered menu (dumb/non-ANSI terminal). The bash tier is what
makes the very first `install.sh` run interactive before gum exists; gum is the
CLI of the same charmbracelet engine as the rejected embedded picker, so it's
used only on re-runs. Change your setup by re-running `bash scripts/wizard.sh`
(or `chezreset` for a full replay).
`[profileDefaults]` in `src/.chezmoidata/modules.toml` mirrors the template's
`$defaults` — `tests/data-model.bats` enforces the match.

**Packages (`packages/`).** `packages/Brewfile` is the core tier (always
installed). Optional layers compose on top: `packages/Brewfile.mac-apps` (gated
by the `macApps` module) and the profile-specific `packages/Brewfile.personal` /
`packages/Brewfile.work` (`packages/` also holds the VS Code + cspell editor
lists). The map is the single source of truth in `src/.chezmoidata/packages.toml`
(paths relative to the repo root); the `02-brew-bundle` hook joins them with
`{{ .chezmoi.workingTree }}` and runs Homebrew's native `brew bundle`
(`--no-upgrade`, so convergence guarantees presence, not freshness — upgrades are
`chezbump`'s job).

**Apply lifecycle (`src/.chezmoiscripts/run_*.sh.tmpl`).** These are the only
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

**Engine code (`scripts/lib/`).** Shared, shellcheckable, testable bash under
`scripts/lib/` (at the repo root, so hooks source it via
`{{ .chezmoi.workingTree }}/scripts/lib/…`): `log.sh` (colors/glyphs + rail-style
log helpers), `obsidian-apply.sh` (vault-seeding engine), `chezmoi-data.sh` (data
reader), `semver.sh`, `tty.sh`. A hook does render-time config, then sources its
lib, then calls the entry point; `02d-obsidian-apply` is the reference shape.

**User-facing commands (`scripts/`).** `chezup.sh` (pull + apply + converge),
`doctor.sh` (`chezdoctor` health check), `bootstrap-auth.sh` (post-install
account + git-signing walkthrough), `macos-defaults.sh`, and `wizard.sh` (the
plain-text setup wizard). Change profile/modules/signing by re-running
`bash scripts/wizard.sh`.

The `install.sh` at the repo root is the one-shot fresh-Mac bootstrap: a small
**hand-written** script (it runs via `curl | bash` before the repo exists, so it
can't source `scripts/lib/*`). It installs only the prerequisites — Xcode CLT,
Homebrew, chezmoi, the repo clone — then hands off to `scripts/wizard.sh` (which
asks the questions and runs `chezmoi init --apply`; passing extra args bypasses
the wizard and goes straight to chezmoi). Edit it directly; it is NOT generated. See
`docs/lifecycle.md`.

**Runtimes are mise, not Homebrew.** Java/Node/Python come from mise: global
defaults in `~/.config/mise/config.toml` (source: `src/dot_config/mise/`),
per-project pins in each project's `mise.toml`. Don't add language runtimes to
Homebrew.

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
for f in src/dot_zshenv src/dot_config/zsh/dot_zprofile; do zsh -n "$f"; done

# Local commit gates mirroring CI (shellcheck, shfmt, typos, commit message).
# Activate once per clone; run across everything on demand:
pre-commit install --install-hooks
pre-commit run --all-files

# Render every template via dry-run apply (catches Go-template/data errors).
# Vary the env to exercise the profile × modules matrix (MODULES is a CSV; empty
# or "none" = no modules; unset = derived from MAC_APPS for back-compat):
PROFILE=personal MODULES=macApps,theme,jvmStack,locale bash scripts/render-check.sh "$PWD"

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
