# Apply lifecycle

How `chezmoi apply` (and therefore `install.sh` / `chezup`) turns this repo into
a configured machine, and the rules the hook scripts follow. This is the doc the
`src/.chezmoiscripts/` hooks and `scripts/lib/` engines point back to.

## Repo split: `src/` vs. root tooling

`.chezmoiroot` (one line, `src`) makes `src/` chezmoi's **source directory**:
everything under it deploys to `$HOME`, and everything at the repo root
(`scripts/`, `packages/`, `tests/`, `docs/`, `install.sh`) is tooling chezmoi
never sees. Inside a hook, `{{ .chezmoi.sourceDir }}` is `…/dotfiles/src`, so
reaching root-level tooling (the `scripts/lib/*` engines, `packages/Brewfile*`)
uses `{{ .chezmoi.workingTree }}` — the git working tree, i.e. the repo root —
instead. That's the one path idiom the hooks rely on.

## The stages

`chezmoi apply` renders the managed files into `$HOME`, then runs the scripts in
`src/.chezmoiscripts/`. Ordering and re-run behavior come entirely from the
filename prefix; the two-digit `NN` orders within a bucket (`02` → `02b` → `02c`
→ …):

| Prefix | When it runs |
|---|---|
| `run_before_NN-…`        | every apply, **before** files are written |
| `run_after_NN-…`         | every apply, **after** files are written |
| `run_once_before_NN-…`   | **first** apply on a machine only |
| `run_onchange_after_NN-…`| only when the script's *rendered* body changes |

Every hook uses `#!/usr/bin/env bash` + `set -euo pipefail` (or `-uo` to continue
past failing items), carries the darwin guard near the top unless it's truly
OS-agnostic, and `exec </dev/tty` before any `sudo`/`read` (chezmoi runs scripts
with stdin closed), degrading gracefully when there's no TTY.

## Convergence guarantee

The design rule that shapes the `02*` hooks:

> Pick `run_after_*` for anything that **converges installed state** (brew, mise,
> plugins) so it reconciles on **every** run. Pick `run_onchange_after_*` for
> state mutated from a **static manifest**, where re-running on unchanged input is
> just noise (VS Code extensions, macOS defaults).

`run_after_02-brew-bundle`, `run_after_02b-mise-install`, and
`run_after_02d-obsidian-apply` are `run_after` on purpose: real installed state
can drift out from under the repo (a package uninstalled by hand, a plugin gone
missing) while the *text* that describes it stays put. Running every apply — each
gated by a fast presence short-circuit so a clean machine is a quick no-op —
means "make this Mac match the repo" always holds, with no separate fix step.

`run_onchange_after_02c/02e/03/04` mutate state from a fixed manifest (a
deprecation list, `.pre-commit-config.yaml`, `packages/vscode-extensions.txt`,
macOS defaults). The action pre-commit or `code` performs is identical regardless
of apply count, so these re-fire only when their embedded content hash changes.

Package convergence uses Homebrew's native `brew bundle` (the `02-brew-bundle`
hook reads the active file set from `src/.chezmoidata/packages.toml`, then runs
`brew bundle --no-upgrade` so it converges *presence*, not freshness). Other
custom logic (e.g. `obsidian-apply.sh`) lives in `scripts/lib/` so it stays
shellcheck-able and unit-tested; hooks are thin drivers that do render-time
config, source their lib (if any), and call the entry point.

## Where each piece lives

Hook paths are under `src/.chezmoiscripts/`; tooling paths (`scripts/`,
`packages/`) are at the repo root.

| Concern | Source |
|---|---|
| Sudo pre-auth | `src/.chezmoiscripts/run_before_00-sudo-cache.sh.tmpl` |
| Homebrew install (first run) | `src/.chezmoiscripts/run_once_before_01-install-homebrew.sh.tmpl` |
| Package convergence | `run_after_02-brew-bundle` (native `brew bundle`, reads `src/.chezmoidata/packages.toml`) |
| Runtime convergence (mise) | `run_after_02b-mise-install` |
| Deprecated-tool cleanup | `run_onchange_after_02c-cleanup-deprecated` |
| Obsidian vault seed | `run_after_02d-obsidian-apply` + `scripts/lib/obsidian-apply.sh` |
| pre-commit hook install | `run_onchange_after_02e-pre-commit-install` |
| VS Code extensions | `run_onchange_after_03-vscode` + `packages/vscode-extensions.txt` |
| macOS defaults | `run_onchange_after_04-macos-defaults` + `scripts/macos-defaults.sh` |
| Closing summary | `run_onchange_after_99-completion` |
| Package tiers | `packages/Brewfile` (core) + `packages/Brewfile.{mac-apps,personal,work}` |
| Data model + wizard | `src/.chezmoi.toml.tmpl` (chezmoi `init` prompt data) + `scripts/wizard.sh` (plain-text front-end) |
| Module catalog + Brewfile map | `src/.chezmoidata/{modules,packages}.toml` (single source of truth) |

## Bootstrap + look & feel

`install.sh` (fresh-Mac bootstrap) and `chezup` (everyday converge) are separate,
plain scripts.

`install.sh` is a small hand-written script fetched via `curl | bash` **before
this repo exists on disk**, so it can't source anything. It installs only the
prerequisites (Xcode CLT → Homebrew → chezmoi → clone), then hands off to
`scripts/wizard.sh` (repo now on disk, so it *can* source `scripts/lib/*`).

The setup questions are chezmoi's own `init` prompt data, defined in
`.chezmoi.toml.tmpl` (`profile`, `signingMode`, and a `modules` multi-select) with
`*Once` semantics so re-running is idempotent. But chezmoi renders those prompts
as an interactive TUI picker that is unreliable under `curl | bash` and some
terminals, so `wizard.sh` is the front-end: it asks each question with plain
`read` from `/dev/tty` and passes the answers to `chezmoi init --apply` via its
`--promptString/-Choice/-Multichoice` flags (no TUI). `bash scripts/wizard.sh` is
the "change my setup" path; `chezreset` is the "set up as new" replay. Passing
extra args to `install.sh` bypasses the wizard and calls `chezmoi init` directly.
Edit `install.sh` directly — it is **not** generated.

Everyday scripts (`chezup`, `doctor`, `bootstrap-auth`, `setup-ollama`, the
obsidian hook) share a tiny logging library, `scripts/lib/log.sh`:

- `ui_init_colors` / `ui_init_glyphs` — palette + Unicode/ASCII glyphs.
- `ui_init_logging` — the rail-style log helpers (`say`/`ok`/`info`/`warn`/
  `fail`/`dim`/`hr` plus `line_prefix`/`node_prefix`); inits colors + glyphs first.

### Shared libraries (`scripts/lib/`)

| Lib | Provides | Sourced by |
|---|---|---|
| `log.sh`             | colors, glyphs, rail-style log helpers          | chezup, bootstrap-auth, setup-ollama, wizard, obsidian hook (doctor uses colors/glyphs) |
| `chezmoi-data.sh`    | `cm_data_json/string/bool`, `cm_toml_*` readers | doctor, wizard |
| `tty.sh`             | `tty_reattach` (stdin → controlling terminal)   | `run_before_00`, `run_after_02`, `run_onchange_after_04` |
| `obsidian-apply.sh`  | the Obsidian vault seed engine                  | `run_after_02d-obsidian-apply` |
| `semver.sh`          | `semver_extract` / `semver_lt`                  | doctor |
| `check-commit-msg.sh`| Conventional-Commit subject validator           | commit-msg pre-commit hook |
