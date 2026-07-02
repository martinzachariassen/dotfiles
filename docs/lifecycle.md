# Apply lifecycle

How `chezmoi apply` (and therefore `install.sh` / `chezup`) turns this repo into
a configured machine, and the rules the hook scripts follow. This is the doc the
`.chezmoiscripts/` hooks and `scripts/lib/` engines point back to.

## The stages

`chezmoi apply` renders the managed files into `$HOME`, then runs the scripts in
`.chezmoiscripts/`. Ordering and re-run behavior come entirely from the filename
prefix; the two-digit `NN` orders within a bucket (`02` → `02b` → `02c` → …):

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
deprecation list, `.pre-commit-config.yaml`, `vscode/extensions.txt`, macOS
defaults). The action pre-commit or `code` performs is identical regardless of
apply count, so these re-fire only when their embedded content hash changes.

The real install/convergence logic lives in `scripts/lib/` (`brew-bundle.sh`,
`obsidian-apply.sh`, …) so it stays shellcheck-able and unit-tested; the hooks
are thin drivers that do render-time config, source their lib, and call the entry
point.

## Where each piece lives

| Concern | Source |
|---|---|
| Sudo pre-auth | `.chezmoiscripts/run_before_00-sudo-cache.sh.tmpl` |
| Homebrew install (first run) | `.chezmoiscripts/run_once_before_01-install-homebrew.sh.tmpl` |
| Package convergence | `run_after_02-brew-bundle` + `scripts/lib/brew-bundle.sh` |
| Runtime convergence (mise) | `run_after_02b-mise-install` |
| Deprecated-tool cleanup | `run_onchange_after_02c-cleanup-deprecated` |
| Obsidian vault seed | `run_after_02d-obsidian-apply` + `scripts/lib/obsidian-apply.sh` |
| pre-commit hook install | `run_onchange_after_02e-pre-commit-install` |
| VS Code extensions | `run_onchange_after_03-vscode` + `vscode/extensions.txt` |
| macOS defaults | `run_onchange_after_04-macos-defaults` + `scripts/macos-defaults.sh` |
| Closing summary | `run_onchange_after_99-completion` |
| Package tiers | `Brewfile` (core) + `brewfiles/Brewfile.{mac-apps,personal,work}` |

## Look & feel — one engine, one look

`install.sh` (fresh-Mac bootstrap) and `chezup` (everyday converge) deliberately
share one visual vocabulary — the same banner, phase headers, prompts, glyphs,
and Catppuccin Frappé palette — so the two feel like one tool.

That engine lives in `scripts/lib/ui.sh` (`ui_init_colors` / `ui_init_glyphs` /
`ui_init_wizard` and the `say`/`ok`/`warn`/`phase_open`/`ui_banner`/`prompt_*`
helpers). `chezup`, `doctor`, and `bootstrap-auth` source it.

`install.sh` is the one exception: it is fetched via `curl | bash` **before this
repo exists on disk**, so it cannot source `ui.sh` and instead carries its own
copy of the same helpers. Keep the two visual contracts in sync when you change
either — the styling in `install.sh` and `ui.sh` is meant to be identical.
