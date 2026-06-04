# Upgrading when upstream changes

Once your machine is on this setup, keeping it in sync with what's pushed upstream is one command in the common case and one slightly bigger command for the rare "the wizard changed" case.

### The 95% case: just pull and apply

```sh
chezup
```

Defined in your `.zshrc`. It does:

1. `git pull --ff-only` in `~/Developer/personal/dotfiles`
2. `chez` — chezmoi status + a single-keypress confirm + `chezmoi apply --force`

That handles everything chezmoi knows how to handle: new dotfiles, edited templates, added/removed workstation packages in any Brewfile, modified scripts, and VS Code settings/extensions. Project-level runtime changes are applied when you `cd` into that project (mise installs any missing pinned versions) or run `mise install` there.

`chezup` is also a no-op when nothing changed — safe to run as often as you like (e.g., wire it into a launchd timer for a daily auto-sync if you want).

### The 5% case: the wizard's data model or chezmoi config changed

Sometimes a push will add a new prompt to the wizard (a new workstation feature toggle, a new boolean for "do you use X?"), or change a chezmoi-level setting like `[apply] force = true` or `[diff] pager`. When that happens, your existing `~/.config/chezmoi/chezmoi.toml` is stale — `chezmoi apply` reads the on-disk config and won't see the new sections. Templates use defensive defaults for feature toggles, but `[apply]`/`[diff]` settings only take effect after a re-init.

To pull the new sections into your on-disk config:

```sh
chezreinit
```

That's `git pull` + `chezmoi init` + `chez`. `chezmoi init` re-renders `chezmoi.toml` from the latest template; `promptOnce` keeps every answer you've already given and only prompts for fields that don't have a value yet. Idempotent — running it on a fully-up-to-date config is a no-op.

**Telltale sign you need `chezreinit` rather than `chezup`:** you're seeing prompts or behaviour from `chezmoi apply` that the docs say should be silent (e.g. per-file `diff/overwrite/skip` prompts after `[apply] force = true` was added, or unpaged diffs after `[diff] pager` was changed).

If you'd rather walk through the full wizard again (e.g., to flip a workstation feature toggle visually rather than by editing TOML), just rerun:

```sh
bash ~/Developer/personal/dotfiles/install.sh
```

It'll detect your existing config during the Mac check, reuse those answers as defaults, and let you choose customize if you want to revisit feature toggles or cleanup behavior.

### How the invalidation rules work

Knowing what triggers what makes the upgrade story less mysterious:

| You edit / pull… | Triggers on next `chezmoi apply` |
|---|---|
| Any file under `dot_*` or `private_dot_*` | chezmoi writes it to `$HOME` |
| A `.tmpl` template | chezmoi re-renders it against your current `[data]` block |
| `Brewfile` or `brewfiles/Brewfile.*` | `run_onchange_after_02-brew-bundle.sh` re-fires (hash comment caught it) |
| `.chezmoi.toml.tmpl` itself | **nothing automatic** — you must run `chezmoi init` (or `chezreinit`) to re-render `~/.config/chezmoi/chezmoi.toml`. This is the only common case where `chezup` alone is insufficient |
| `scripts/macos-defaults.sh` | `run_onchange_after_04-macos-defaults.sh` re-fires (it embeds a sha256 `include` of this script), re-applying your defaults. A routine apply that *doesn't* touch this script is a no-op, so you don't get a sudo prompt every time. To re-apply without editing the script, run the `macos-defaults` alias |

If you forget which path you're on, `chezdiff` shows you everything actionable at once: chezmoi's dotfile diff, brew-bundle drift across every tracked Brewfile, and `run_*` scripts that would re-fire for reasons other than the normal every-apply hooks. It's the "what would chezup actually do" preview.

### Cleaning up packages from features you've turned off

Disabling a feature toggle stops that Brewfile from being re-applied, but does **not** uninstall the packages it pulled in — intentional, so you don't lose tools you might still use. To actually remove the current mac-apps feature packages:

```sh
brew bundle cleanup --force --file=~/Developer/personal/dotfiles/brewfiles/Brewfile.mac-apps
```

`chezaudit` (alias) shows you packages currently installed that aren't tracked in any Brewfile, which is useful when you've manually `brew install`ed something and want to decide whether to promote it into a workstation Brewfile, pin it in a project's `mise.toml`, or remove it.

### Why the Brewfiles aren't version-pinned

Every formula and cask in `Brewfile` and `brewfiles/Brewfile.*` is **unpinned** —
`brew bundle` always installs whatever is current in Homebrew at apply time.
This is deliberate, not an oversight:

- **The Brewfiles describe a fresh-Mac baseline, not a frozen snapshot.** The
  goal is "a new machine ends up with the current versions of these tools,"
  which is exactly what unpinned gives you.
- **Homebrew no longer supports a Brewfile lockfile.** The old
  `Brewfile.lock.json` mechanism was removed from `brew bundle`; there is no
  `--no-lock` flag and no supported way to make `brew bundle` reinstall an
  arbitrary older version of a formula. Committing a lockfile would be a dead
  file. (The `Brewfile.lock.json` entry in `.chezmoiignore` is just a guard in
  case one is ever generated locally — nothing writes it.)
- **Per-project reproducibility lives in mise, not Homebrew.** When a project
  needs a pinned language runtime (a specific JDK, Node, Python…), that belongs
  in the project's committed `mise.toml`, which *does* pin exact versions and
  travels with the repo. Homebrew is for workstation-wide tools where "latest"
  is the right answer.

If you ever need a specific older version of a workstation tool, install it
ad-hoc (`brew install foo@1.2`) and treat it as untracked — `chezaudit` will
remind you it isn't in a Brewfile.

### What to do after a long absence (machine sitting idle for weeks)

```sh
chezreinit         # pull + init + apply — handles data-model drift in one shot
chezbump           # brew update/upgrade + mise upgrade
chezdoctor         # full health check — surfaces anything that broke while you were away
```
