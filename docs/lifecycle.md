# Apply lifecycle

How `chezmoi apply` (and therefore `install.sh` / `chezup`) turns this repo into
a configured machine, and the rules the hook scripts follow. The
`src/.chezmoiscripts/` hooks and `scripts/lib/` engines point back to this doc.

For the repo split, naming conventions, and `scripts/` layout, see
[architecture.md](architecture.md). The one path idiom worth repeating: inside a
hook `{{ .chezmoi.sourceDir }}` is `…/dotfiles/src`, so root-level tooling
(`scripts/lib/*`, `packages/Brewfile*`) is reached via
`{{ .chezmoi.workingTree }}` (the git working tree = repo root).

## The stages

`chezmoi apply` renders the managed files into `$HOME`, then runs the scripts in
[`src/.chezmoiscripts/`](../src/.chezmoiscripts). Ordering and re-run behavior
come entirely from the filename prefix; the two-digit `NN` orders within a bucket
(`02` → `02b` → `02e` → …).

| Prefix | When it runs |
|---|---|
| `run_before_NN-…` | every apply, **before** files are written |
| `run_after_NN-…` | every apply, **after** files are written |
| `run_once_before_NN-…` | **first** apply on a machine only |
| `run_onchange_after_NN-…` | only when the script's *rendered* body changes |

Every hook uses `#!/usr/bin/env bash` + `set -euo pipefail` (or `-uo` to
continue past failing items), carries the darwin guard near the top unless
it's truly OS-agnostic, and `exec </dev/tty` before any `sudo`/`read` (chezmoi
runs scripts with stdin closed), degrading gracefully when there's no TTY.

## Convergence guarantee

The design rule that shapes the `02*` hooks:

> Pick `run_after_*` for anything that **converges installed state** (brew,
> mise, plugins) so it reconciles on **every** run. Pick `run_onchange_after_*`
> for state mutated from a **static manifest**, where re-running on unchanged
> input is just noise (VS Code extensions, macOS defaults).

`run_after_02-brew-bundle` and `run_after_02b-mise-install` are `run_after` on
purpose: real installed state can drift out from under the repo (a package
uninstalled by hand, a plugin gone missing) while the *text* describing it
stays put. Running every apply — each gated by a fast presence
short-circuit, so a clean machine is a quick no-op — keeps "make this Mac
match the repo" always true, with no separate fix step.

`run_onchange_after_02e/03/04/05` mutate state from a fixed manifest
(`.pre-commit-config.yaml`, `packages/vscode-extensions.txt`, macOS defaults,
the storecode installer). The action performed is identical regardless of
apply count, so these re-fire only when their embedded content hash changes.

Package convergence uses Homebrew's native `brew bundle`: the
`02-brew-bundle` hook reads the active file set from
[`src/.chezmoidata/packages.toml`](../src/.chezmoidata/packages.toml), then
runs `brew bundle --no-upgrade` to converge *presence*, not freshness. It
only *adds* — freshness is `chezbump`'s job, and *removal* (uninstalling
packages the Brewfile no longer lists) is `chezmirror`'s: an apply must never
silently uninstall, so `chez` flags untracked packages and `chezmirror`
reconciles them behind a confirm. VS Code extensions are the deliberate
exception: they carry no data and are trivial to reinstall, so
`run_onchange_after_03-vscode` mirrors them outright — installing what
`packages/vscode-extensions.txt` lists and pruning what it doesn't — with
`chezdoctor` surfacing the drift read-only. Some extensions also drop a
top-level dir in `$HOME` (`.sonarlint`, `.lemminx`, …); those are **not**
touched by an apply — `chezclean` removes them on demand once their owning
extension is gone (the `extension` field in `cleanup.owners` links each dir
to its extension). Other custom logic lives in `scripts/lib/` so it stays
shellcheck-able and unit-tested; hooks are thin drivers that do render-time
config, source their lib (if any), and call the entry point.

## Reconciling untracked dotfiles (chezclean)

Presence-convergence keeps installed *state* matching the repo; a parallel,
**manual** step keeps the dotfiles matching it *structurally*. An apply never
deletes — it only renders what the repo tracks — so untracked cruft (a dir some
tool dropped, config for a package you've since removed) accumulates until you
reconcile it. That's [`chezclean`](commands.md)'s job: the confirm-gated file
analogue of `chezmirror`.

`chezclean` reconciles two scopes against the repo, both reading their keep-list
from [`src/.chezmoidata/cleanup.toml`](../src/.chezmoidata/cleanup.toml):

- the **top level of `$HOME`** — untracked `~/.*` entries, spared by
  `cleanup.keepHome` (it can't be `exact_`: it holds `~/Library`,
  `~/Documents`, and other user data);
- **`~/.config`** — untracked `~/.config/X`, spared by `cleanup.keepConfig`:
  auth/state dirs like `op`, `gh`, `gcloud`, and chezmoi's own
  `~/.config/chezmoi`.

Neither scope descends past its immediate children, so a managed subdir
(`nvim`, `zsh`, …) keeps its own untracked contents (caches, `.zcompdump`,
local overrides). Nothing is removed without a confirmation (or an explicit
`--all`/`YES=1`), and never at all without a controlling terminal.

`chezclean` is **tool-aware**: config whose owning tool is still present is
kept automatically and never offered, where "present" is the union of three
signals — its brew package is installed, its command is on PATH (so tools
from mise/gcloud/npm count too), **or** its owning VS Code extension is in
`code --list-extensions`; uninstall the tool (or drop the extension) and its
leftovers re-surface as removable. Most tools are matched by a stem
heuristic (`command -v <name-minus-dot>`, e.g. `.gradle`→`gradle`); the
`cleanup.owners` map supplies only the aliases where the dir name and the
tool's command/package/extension diverge (`.kube`→`kubectl`, `.m2`→`mvn`
from mise, `.sonarlint`→the `sonarsource.sonarlint-vscode` extension).
`cleanup.toml` is the single source of truth for all three lists
(`keepConfig`, `keepHome`, `owners`), so the two scopes can't drift apart.

Dropped **Homebrew packages** are reconciled the same way, by hand:
`chezmirror` runs `brew bundle cleanup` to uninstall anything no longer in a
Brewfile, then `brew autoremove` to prune orphaned dependencies, while
`chezaudit`/`chezdoctor` report the drift read-only. Nothing about removal is
automatic: if a machine drifts, its owner runs `chezmirror` and `chezclean`
to bring it back in line. To do both package directions in one step —
install what the Brewfiles declare, then remove what they don't —
`chezsync` chains `chezup` and `chezmirror` (files stay with `chezclean`).

## Where each piece lives

Hook paths are under `src/.chezmoiscripts/`; tooling paths (`scripts/`,
`packages/`) are at the repo root.

| Concern | Source |
|---|---|
| Sudo pre-auth | `run_before_00-sudo-cache.sh.tmpl` (keeper: `scripts/lib/sudo.sh`) |
| Homebrew install (first run) | `run_once_before_01-install-homebrew.sh.tmpl` (installer: `scripts/lib/homebrew.sh`) |
| Package convergence | `run_after_02-brew-bundle` (native `brew bundle`, reads `packages.toml`) |
| Runtime convergence (mise) | `run_after_02b-mise-install` |
| Homebrew package cleanup (confirm-gated) | `chezmirror` / `chezaudit` (zsh verbs) → `brew bundle cleanup` + `brew autoremove` |
| Untracked dotfile cleanup (confirm-gated) | `scripts/bin/clean.sh` (`chezclean`) + `cleanup.keepHome` (`$HOME`) + `cleanup.keepConfig` (`~/.config`) |
| chezclean tool-ownership map (keep-while-installed; package/binary/extension) | `src/.chezmoidata/cleanup.toml` (`cleanup.owners`) |
| storecode install (work profile) | `run_onchange_after_05-storecode` + `src/.chezmoidata/storecode.toml` |
| pre-commit hook install | `run_onchange_after_02e-pre-commit-install` |
| VS Code extension mirror | `run_onchange_after_03-vscode` + `packages/vscode-extensions.txt` + `scripts/lib/vscode.sh` (drift check in `scripts/bin/doctor.sh`) |
| VS Code extension-owned `$HOME`-dir cleanup (on demand) | `chezclean` + `cleanup.owners` (`extension`) |
| macOS defaults | `run_onchange_after_04-macos-defaults` + `scripts/bin/macos-defaults.sh` (shares `scripts/lib/sudo.sh`'s keeper; skips it under a chezmoi apply via `DOTFILES_SUDO_KEPT_WARM=1`) |
| Closing summary | `run_onchange_after_99-completion` |
| Package tiers | `packages/Brewfile` (core) + `packages/Brewfile.{mac-apps,personal,work}` |
| Data model + wizard | `src/.chezmoi.toml.tmpl` + `scripts/bin/wizard.sh` |
| Module catalog + Brewfile map | `src/.chezmoidata/{modules,packages}.toml` |

## Bootstrap

`install.sh` (fresh-Mac bootstrap) and `chezup` (everyday converge) are
separate, plain scripts — see [install.md](install.md) and
[commands.md](commands.md).

`install.sh` is a small hand-written script fetched via `curl | bash`
**before this repo exists on disk**, so it can't source anything — its
Homebrew-install step is necessarily its own inline copy of what
`scripts/lib/homebrew.sh` does for `run_once_before_01` below. It installs
only the prerequisites (Xcode CLT → Homebrew → chezmoi → clone), then hands
off to `scripts/bin/wizard.sh` (repo now on disk, so it *can* source
`scripts/lib/*`). The wizard asks the setup questions and feeds them to
`chezmoi init --apply`, whose `--apply` runs the hooks above. See
[packages.md](packages.md#the-wizard) for the wizard's three prompt tiers.

The everyday verbs (`chezup`, `chezdoctor`, …) are shell functions that bake
their helper-script path into `~/.config/zsh/.zshrc` **at apply time**.
Because a `git pull` never rewrites the live rc, a restructure that moves a
script can strand a machine that pulled but hasn't re-applied. The functions
self-heal via `_chez_run`; the one un-fixable case (an rc predating that
helper) and its manual recovery are in
[commands.md](commands.md#when-a-command-says-its-script-is-missing).
