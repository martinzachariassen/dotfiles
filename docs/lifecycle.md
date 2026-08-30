# Apply lifecycle

How `chezmoi apply` (and therefore `install.sh` / `chezup`) turns this repo into
a configured machine, and the rules the hook scripts follow. The
`src/.chezmoiscripts/` hooks and `scripts/lib/` engines point back to this doc.

For the repo split, naming conventions, and `scripts/` layout, see
[architecture.md](architecture.md). The one path idiom worth repeating: inside a
hook `{{ .chezmoi.sourceDir }}` is `…/dotfiles/src`, so root-level tooling
(`scripts/lib/*`, `features/brew/Brewfile*`) is reached via
`{{ .chezmoi.workingTree }}` (the git working tree = repo root).

## The stages

`chezmoi apply` renders the managed files into `$HOME`, then runs the scripts in
[`src/.chezmoiscripts/`](../src/.chezmoiscripts). chezmoi splits them into
`before` and `after` passes, and **within a pass it sorts by *target* name —
the filename with its `run_`/`once_`/`onchange_` attributes stripped.** So it is
the two-digit `NN` alone that orders `02-brew-bundle` → `02b-mise-install` →
`02e-pre-commit-install` → `03-vscode` → `04-macos-defaults` → `05-storecode`
→ `99-completion`; `run_after_*` and `run_onchange_after_*` interleave freely.
Confirm with `chezmoi status`, which prints the stripped target names.

That matters when adding a hook: the "the tool exists by now" assumption in
`02e`/`03`/`05` holds only because their `NN` is greater than brew-bundle's.
A new `run_onchange_after_01-*` would land *before* it.

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
(`.pre-commit-config.yaml`, `features/vscode/extensions.txt`, macOS defaults,
the storecode installer). The action performed is identical regardless of
apply count, so these re-fire only when their embedded content hash changes.

Package convergence uses Homebrew's native `brew bundle`: the
`02-brew-bundle` hook reads the active file set from
[`src/.chezmoidata/brew.toml`](../src/.chezmoidata/brew.toml), then
runs `brew bundle --no-upgrade` to converge *presence*, not freshness. Casks
that ship an Apple installer package need admin access, so the hook confirms
the sudo ticket (asking on a clean screen, before the progress bar) and keeps
it warm for the length of the bundle rather than letting a prompt surface from
behind the bar. It
only *adds* — freshness is `chezbump`'s job, and *removal* (uninstalling
packages the Brewfile no longer lists) is `chezmirror`'s: an apply must never
silently uninstall, so `chezapply` flags untracked packages and `chezmirror`
reconciles them behind a confirm. VS Code extensions are the deliberate
exception: they carry no data and are trivial to reinstall, so
`run_onchange_after_03-vscode` mirrors them outright — installing what
`features/vscode/extensions.txt` lists and pruning what it doesn't — with
`chezdoctor` surfacing the drift read-only. Some extensions also drop a
top-level dir in `$HOME` (`.sts4`, `.lemminx`, …); those are **not**
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
reconcile it. That's `chezclean`'s job: the confirm-gated file analogue of
`chezmirror`.

It reconciles two scopes — the top level of `$HOME` and `~/.config` — against
what chezmoi manages, keeps anything whose owning tool is still installed, and
removes only what you confirm. The full model, including the three
tool-presence signals and the keep-lists, is in
[features/clean](../features/clean/README.md).

Dropped **Homebrew packages** are reconciled the same way, by hand:
`chezmirror` runs `brew bundle cleanup` to uninstall anything no longer in a
Brewfile, then `brew autoremove` to prune orphaned dependencies, while
`chezstatus`/`chezdoctor` report the drift read-only. "No longer in a Brewfile"
means no Brewfile **active on this machine** — core, the enabled modules and
this profile's tier. Both directions resolve that set through
[`features/brew/lib/tiers.sh`](../features/brew/lib/tiers.sh), so install and
removal can't disagree: moving a package to the other profile's tier makes it
removable here, exactly as deleting it would. The removal side fails closed —
an unresolvable tier set offers nothing, never more. Nothing about removal is
automatic: if a machine drifts, its owner runs `chezmirror` and `chezclean`
to bring it back in line. To do both package directions in one step —
install what the Brewfiles declare, then remove what they don't —
`chezreconcile` chains `chezup` and `chezmirror` (files stay with `chezclean`).

## Where each piece lives

Hook paths are under `src/.chezmoiscripts/`; tooling paths (`scripts/`,
`packages/`) are at the repo root.

| Concern | Source |
|---|---|
| Sudo pre-auth | `run_before_00-sudo-cache.sh.tmpl` (keeper: `core/sudo.sh`); `run_after_02-brew-bundle` re-checks and asks again before its progress bar starts, if the ticket lapsed |
| Homebrew install (first run) | `run_once_before_01-install-homebrew.sh.tmpl` (installer: `features/brew/lib/homebrew.sh`) |
| Package convergence | `run_after_02-brew-bundle` (native `brew bundle`, reads `brew.toml`) |
| Runtime convergence (mise) | `run_after_02b-mise-install` |
| Homebrew package cleanup (confirm-gated) | `chezmirror` / `chezstatus` (zsh verbs) → `brew bundle cleanup` + `brew autoremove` |
| Active Brewfile tier set (shared by install check, cleanup, doctor) | `features/brew/lib/tiers.sh` (`brew_active_files`, reads `brew.toml` via `chezmoi data`) |
| Untracked dotfile cleanup (confirm-gated) | `features/clean/cli.sh` (`chezclean`) + `cleanup.keepHome` (`$HOME`) + `cleanup.keepConfig` (`~/.config`) |
| chezclean tool-ownership map (keep-while-installed; package/binary/extension) | `src/.chezmoidata/clean.toml` (`cleanup.owners`) |
| storecode install (work profile) | `run_onchange_after_05-storecode` + `src/.chezmoidata/storecode.toml` |
| pre-commit hook install | `run_onchange_after_02e-pre-commit-install` |
| VS Code extension mirror | `run_onchange_after_03-vscode` (a thin template) + `features/vscode/{hook,lib}.sh` + `features/vscode/extensions.txt` (drift check in `scripts/bin/doctor.sh`) |
| VS Code extension-owned `$HOME`-dir cleanup (on demand) | `chezclean` + `cleanup.owners` (`extension`) |
| macOS defaults | `run_onchange_after_04-macos-defaults` + `features/macos/cli.sh` (shares `core/sudo.sh`'s keeper; skips it under a chezmoi apply via `DOTFILES_SUDO_KEPT_WARM=1`) |
| Closing summary | `run_onchange_after_99-completion` |
| Package tiers | `features/brew/Brewfile` (core) + `features/brew/Brewfile.{mac-apps,personal,work,apple-dev}` |
| Data model + wizard | `src/.chezmoi.toml.tmpl` + `features/setup/cli.sh` |
| Module catalog + Brewfile map | `src/.chezmoidata/{modules,packages}.toml` |

## Bootstrap

`install.sh` (fresh-Mac bootstrap) and `chezup` (everyday converge) are
separate, plain scripts — see [install.md](install.md) and
[commands.md](commands.md).

`install.sh` is a small hand-written script fetched via `curl | bash`
**before this repo exists on disk**, so it can't source anything — its
Homebrew-install step is necessarily its own inline copy of what
`features/brew/lib/homebrew.sh` does for `run_once_before_01` below. It installs
only the prerequisites (Xcode CLT → Homebrew → chezmoi → clone), then hands
off to `features/setup/cli.sh` (repo now on disk, so it *can* source
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
