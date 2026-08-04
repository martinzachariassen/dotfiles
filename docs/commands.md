# Commands

The everyday surface is **two verbs plus a health check**. Both verbs end in the
same `chezmoi apply`, which reconciles *real installed state* on every run, so it
always installs what the Brewfile declares. It never *uninstalls*: `chez` only
flags packages you have but the Brewfile doesn't, and `chezmirror` reconciles
that removal direction on demand. `chezmirror` is **removal-only** — the install
direction is what every `chez`/`chezup` already does; `chezsync` chains the two
(`chezup` then `chezmirror`) when you want a full both-directions package
reconcile in one step.

The verbs are defined in
[`src/dot_config/zsh/dot_zshrc.tmpl`](../src/dot_config/zsh/dot_zshrc.tmpl) and
delegate to the scripts in [`scripts/bin/`](../scripts/bin).

## Everyday

| Command | What it does |
|---|---|
| `chezup` | **Converge this Mac to the repo:** pull the latest changes, preview the drift, then apply. The everyday command. |
| `install.sh` | **Bootstrap a new Mac** from scratch (the same apply path under the hood — see [install.md](install.md)). |
| `chezdoctor` | Read-only **health check** for repo, chezmoi, brew, auth, signing, mise, and shell layout. |

**`chezup` runs in three phases**, honouring `DRY_RUN=1` (print, don't run) and
`YES=1` (skip the confirm gate), and passing any trailing arguments through to
`chezmoi apply` (e.g. `chezup -v`):

1. **Update repo** — `git pull --ff-only` in the source dir; reports how many
   commits arrived.
2. **Review pending changes** — `chezmoi status` lists the drift between repo
   and `$HOME` (`A` add, `M` modify, `D` remove). Stops here if nothing drifted.
3. **Apply** — one confirmation gate, then `chezmoi apply --force`.

## When a command says its script is missing

The verbs are shell functions with the helper-script path **baked into
`~/.config/zsh/.zshrc` at apply time** (fast — no `chezmoi source-path`
subprocess per call). A `git pull` updates the repo on disk but never rewrites
the live rc. So if a repo restructure **moves or renames a script** (the
`scripts/` → `scripts/bin/` regroup, say), a machine that pulled but hasn't
re-applied has a function pointing at a path that no longer exists.

The wrappers self-heal through `_chez_run`: on a missing script they run
`git pull` + `chezmoi apply` to regenerate the functions with corrected paths,
then `exec zsh` to reload. You'll see:

```text
dotfiles: …/scripts/bin/chezup.sh is missing — this shell's config predates a repo change.
  re-syncing this machine (git pull + chezmoi apply)…
  synced — reloading your shell. Re-run your command.
```

**The one case this can't fix automatically:** a `.zshrc` applied *before*
`_chez_run` itself existed — you can't repair a broken bootstrap from inside the
broken file. Recover it once by running the script directly (bypassing the
stale function), then reload:

```sh
bash ~/Developer/personal/dotfiles/scripts/bin/chezup.sh   # pull + preview + apply
exec zsh
```

From then on the self-heal is in your rc and any future script move is
automatic. If the script path itself differs in your clone, the
provider-agnostic fallback is `chezmoi apply && exec zsh` (`chezmoi` is on
`PATH` via Homebrew and reads `.chezmoiroot` itself).

## Changing your setup

Change your profile, optional modules, or signing by re-running the plain-text
wizard, which overrides your saved answers:

```sh
chezreset               # re-ask profile / modules / signing, then apply
```

`chezreinit` is different: it runs plain `chezmoi init`, which — via chezmoi's
`prompt*Once` functions — keeps every answer you've given and only asks for
setup keys still blank. So it fills in newly added questions but never lets you
re-choose existing ones; reach for `chezreset` for that. See
[packages.md](packages.md#the-wizard) for how the wizard works.

## Advanced / occasional helpers

| Command | What it does |
|---|---|
| `chezhelp` | Print every dotfiles verb, grouped, one line each. Static text — instant, no subprocesses. The entry point when you forget a command. |
| `dotfiles` | Jump to the source repo (with args, points you at `chezreset` / `chezreinit` / `chezhelp`). |
| `chez` | Apply without pulling — the building block `chezup` calls. Flags Brewfile drift (packages installed but untracked); never uninstalls. |
| `chezdiff` | Plain-language drift explainer: translates `chezmoi status` into two labelled sections — what `chez` would push (repo → `$HOME`) and managed files you edited locally (`$HOME` drift). Read-only. `chezdiff PATH` or `chezdiff -v` drops to raw `chezmoi diff`. |
| `chezreinit` | Pull, run plain `chezmoi init` to fill in **newly added** data-model keys, then apply. Keeps existing answers — use after wizard/data-model changes, not to re-choose. |
| `chezreset` | Set up this Mac **as new**: reset chezmoi's persistent state so `run_once_*` (and `run_onchange_*`) hooks fire again, re-ask the full wizard (overriding saved answers), then apply. Confirm-gated; doesn't uninstall packages or delete files. |
| `chezbump` | Routine dependency upgrade (`brew update && brew upgrade` + `mise upgrade`). |
| `chezaudit` | List Homebrew packages installed locally but not tracked in any Brewfile (reports only). |
| `chezmirror` | Enforce the Brewfile as truth in the removal direction: preview the untracked items (all tiers — formulae, casks, orphaned taps), then confirm each removal **one at a time** (via `gum` when installed); casks go through `--cask`, taps through `brew untap`. Pass `--all` (aliases `-a`, `--yes`, `-y`) to remove the **whole** set after one confirmation, or `YES=1 chezmirror` to accept-all with no prompt. Requires a TTY either way. **Removal only** — installs happen via `chez`/`chezup`; `chezsync` runs both. |
| `chezsync` | **Full package reconcile in one step:** `chezup` (converge + install what the Brewfiles declare) then `chezmirror` (uninstall what they don't). `chezup` only adds and `chezmirror` only removes; `chezsync` does both directions. Untracked *files* stay separate — that's `chezclean`. Honours `DRY_RUN=1` (previews both directions, using `chezaudit` for the removal side so nothing is touched) and `YES=1` (skips both confirm gates); trailing args pass through to `chezup` → `chezmoi apply`. |
| `chezclean` | The **file** analogue of `chezmirror`: reconcile untracked dotfiles to what chezmoi manages, across two scopes — the top level of `$HOME` (keep-list `cleanup.keepHome`) and `~/.config` (keep-list `cleanup.keepConfig`), both in [`src/.chezmoidata/cleanup.toml`](../src/.chezmoidata/cleanup.toml). Lists the untracked entries — everything that chezmoi neither manages nor a keep-list spares — then removes only what you confirm **one at a time** (via `gum` when installed). **Tool-aware:** config whose owning tool is still present is kept automatically — the union of three signals: the tool's brew package is installed, its command is on PATH (mise/gcloud tools count too), **or** its owning VS Code extension is in `code --list-extensions`; uninstall the tool (or drop the extension) and its config re-surfaces as removable. Most tools are matched by a stem heuristic (`command -v <name-minus-dot>`, e.g. `.gradle`→`gradle`); the `cleanup.owners` map holds only the aliases where the dir name and the command/package/extension diverge (`.kube`→`kubectl`, `.m2`→`mvn`, `.sonarlint`→`sonarsource.sonarlint-vscode`). Offered entries are labelled `orphan` (a known tool, now gone) or `untracked` (no known owner); `-v`/`--verbose` also lists what tool-ownership kept. Pass `--all` (`-a`/`--yes`/`-y`) to remove the whole set after one confirmation, or `YES=1 chezclean` to accept-all; both need a TTY. `DRY_RUN=1` (or `-n`/`--dry-run`) previews and works headless. **Safe by construction:** only names beginning with `.` are ever considered (so `~/Library`, `~/Documents`, … are structurally out of scope), it never descends past an immediate child, and it removes nothing without a controlling terminal. Keep an entry for good by adding it to `cleanup.keepHome`/`cleanup.keepConfig` (or, if it's a tool whose dir name diverges from its command, map it in `cleanup.owners`). |

> **Why apply never uninstalls.** An apply must be safe to run at any time, so
> it only *adds* presence. Freshness is `chezbump`'s job; *removal* is
> `chezmirror`'s, always behind a confirm. See
> [lifecycle.md](lifecycle.md#convergence-guarantee).

> **`~/.config` is reconciled by `chezclean` too.** It's a normal `dot_config`
> dir, so an apply never prunes it; `chezclean` handles untracked
> `~/.config/X` (keep-list `cleanup.keepConfig`) alongside the top level of
> `$HOME`. See
> [lifecycle.md](lifecycle.md#reconciling-untracked-dotfiles-chezclean).
