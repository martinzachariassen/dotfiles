# Apply lifecycle

How `chezmoi apply` (and therefore `install.sh` / `chezup`) turns this repo into
a configured machine, and the rules the hook scripts follow. This is the doc the
`src/.chezmoiscripts/` hooks and `scripts/lib/` engines point back to.

For the repo split, naming conventions, and how `scripts/` is laid out, see
[architecture.md](architecture.md) — the one path idiom worth repeating here is
that inside a hook `{{ .chezmoi.sourceDir }}` is `…/dotfiles/src`, so root-level
tooling (`scripts/lib/*`, `packages/Brewfile*`) is reached via
`{{ .chezmoi.workingTree }}` (the git working tree = repo root).

## The stages

`chezmoi apply` renders the managed files into `$HOME`, then runs the scripts in
[`src/.chezmoiscripts/`](../src/.chezmoiscripts). Ordering and re-run behavior
come entirely from the filename prefix; the two-digit `NN` orders within a bucket
(`02` → `02b` → `02c` → …):

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

`run_after_02-brew-bundle` and `run_after_02b-mise-install` are `run_after` on
purpose: real installed state can drift out from under the repo (a package
uninstalled by hand, a plugin gone missing) while the *text* that describes it
stays put. Running every apply — each gated by a fast presence short-circuit so a
clean machine is a quick no-op — means "make this Mac match the repo" always
holds, with no separate fix step.

`run_onchange_after_02c/02e/03/04` mutate state from a fixed manifest (a
deprecation list, `.pre-commit-config.yaml`, `packages/vscode-extensions.txt`,
macOS defaults). The action pre-commit or `code` performs is identical regardless
of apply count, so these re-fire only when their embedded content hash changes.

Package convergence uses Homebrew's native `brew bundle` (the `02-brew-bundle`
hook reads the active file set from
[`src/.chezmoidata/packages.toml`](../src/.chezmoidata/packages.toml), then runs
`brew bundle --no-upgrade` so it converges *presence*, not freshness). It only
ever *adds* — freshness is `chezbump`'s job, and *removal* (uninstalling packages
the Brewfile no longer lists) is `chezmirror`'s: an apply must never silently
uninstall, so `chez` just flags untracked packages and `chezmirror` reconciles
them behind a confirm. VS Code extensions are the deliberate exception to the
"never silently uninstall" rule: they carry no data and are trivial to reinstall,
so `run_onchange_after_03-vscode` mirrors them outright — installing what
`packages/vscode-extensions.txt` lists and pruning what it doesn't — on apply,
with `chezdoctor` surfacing the drift read-only. Other custom logic lives in
`scripts/lib/` so it stays shellcheck-able and unit-tested; hooks are thin
drivers that do render-time config, source their lib (if any), and call the entry
point.

## Where each piece lives

Hook paths are under `src/.chezmoiscripts/`; tooling paths (`scripts/`,
`packages/`) are at the repo root.

| Concern | Source |
|---|---|
| Sudo pre-auth | `run_before_00-sudo-cache.sh.tmpl` |
| Homebrew install (first run) | `run_once_before_01-install-homebrew.sh.tmpl` |
| Package convergence | `run_after_02-brew-bundle` (native `brew bundle`, reads `packages.toml`) |
| Runtime convergence (mise) | `run_after_02b-mise-install` |
| Deprecated-tool cleanup | `run_onchange_after_02c-cleanup-deprecated` |
| pre-commit hook install | `run_onchange_after_02e-pre-commit-install` |
| VS Code extension mirror | `run_onchange_after_03-vscode` + `packages/vscode-extensions.txt` + `scripts/lib/vscode.sh` (drift check in `scripts/bin/doctor.sh`) |
| macOS defaults | `run_onchange_after_04-macos-defaults` + `scripts/bin/macos-defaults.sh` |
| Closing summary | `run_onchange_after_99-completion` |
| Package tiers | `packages/Brewfile` (core) + `packages/Brewfile.{mac-apps,personal,work}` |
| Data model + wizard | `src/.chezmoi.toml.tmpl` + `scripts/bin/wizard.sh` |
| Module catalog + Brewfile map | `src/.chezmoidata/{modules,packages}.toml` |

## Bootstrap

`install.sh` (fresh-Mac bootstrap) and `chezup` (everyday converge) are separate,
plain scripts — see [install.md](install.md) and [commands.md](commands.md).

`install.sh` is a small hand-written script fetched via `curl | bash` **before
this repo exists on disk**, so it can't source anything. It installs only the
prerequisites (Xcode CLT → Homebrew → chezmoi → clone), then hands off to
`scripts/bin/wizard.sh` (repo now on disk, so it *can* source `scripts/lib/*`).
The wizard asks the setup questions and feeds them to `chezmoi init --apply` —
`--apply` runs the hooks above. See [packages.md](packages.md#the-wizard) for the
wizard's three prompt tiers.

The everyday verbs (`chezup`, `chezdoctor`, …) are shell functions that bake
their helper-script path into `~/.config/zsh/.zshrc` **at apply time**. Because a
`git pull` never rewrites the live rc, a restructure that moves a script can
strand a machine that pulled but hasn't re-applied. The functions self-heal via
`_chez_run`; the one un-fixable case (an rc predating that helper) and its manual
recovery are in
[commands.md](commands.md#when-a-command-says-its-script-is-missing).
