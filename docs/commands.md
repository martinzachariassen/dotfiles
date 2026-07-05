# Commands

The whole everyday surface is **two verbs plus a health check**. Both verbs end
in the same `chezmoi apply`, which reconciles *real installed state* on every
run — so it always installs what the Brewfile declares. It never *uninstalls*,
though: `chez` only flags packages you have but the Brewfile doesn't, and
`chezmirror` reconciles that removal direction on demand.

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
2. **Review pending changes** — `chezmoi status` lists the drift between the repo
   and `$HOME` (`A` add, `M` modify, `D` remove). If nothing drifted, it stops
   here.
3. **Apply** — one confirmation gate, then `chezmoi apply --force`.

## Changing your setup

Change your profile, optional modules, or signing by re-running the plain-text
wizard, which overrides your saved answers:

```sh
chezreset               # re-ask profile / modules / signing, then apply
```

`chezreinit` is a different tool: it runs plain `chezmoi init`, which — via
chezmoi's `prompt*Once` functions — keeps every answer you've already given and
only asks for setup keys still blank. So it fills in newly-added questions but
never lets you re-choose existing ones; reach for `chezreset` for that. See
[packages.md](packages.md#the-wizard) for how the wizard itself works.

## Advanced / occasional helpers

| Command | What it does |
|---|---|
| `dotfiles` | Jump to the source repo (with args, points you at `chezreset` / `chezreinit`). |
| `chez` | Apply without pulling — the building block `chezup` calls. Flags Brewfile drift (packages installed but untracked); never uninstalls. |
| `chezreinit` | Pull, run plain `chezmoi init` to fill in **newly-added** data-model keys, then apply. Keeps existing answers — use after wizard/data-model changes, not to re-choose. |
| `chezreset` | Set up this Mac **as new**: reset chezmoi's persistent state so `run_once_*` (and `run_onchange_*`) hooks fire again, re-ask the full wizard (overriding saved answers), then apply. Confirm-gated; doesn't uninstall packages or delete files. |
| `chezbump` | Routine dependency upgrade (`brew update && brew upgrade` + `mise upgrade`). |
| `chezaudit` | List Homebrew packages installed locally but not tracked in any Brewfile (drift detection; reports only). |
| `chezmirror` | Enforce the Brewfile as truth in the removal direction: preview, then (confirm-gated) `brew bundle cleanup --force` to uninstall everything untracked. |

> **Why apply never uninstalls.** An apply must be safe to run at any time, so it
> only ever *adds* presence. Freshness is `chezbump`'s job; *removal* is
> `chezmirror`'s, always behind a confirm. See
> [lifecycle.md](lifecycle.md#convergence-guarantee).
