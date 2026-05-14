# Upgrading when upstream changes

Once your machine is on this setup, keeping it in sync with what's pushed upstream is one command in the common case and one slightly bigger command for the rare "the wizard changed" case.

### The 95% case: just pull and apply

```sh
chezup
```

Defined in your `.zshrc`. It does:

1. `git pull --ff-only` in `~/Dev/Personal/dotfiles`
2. `chez` — chezmoi status + a single-keypress confirm + `chezmoi apply -v --force`

That handles everything chezmoi knows how to handle: new dotfiles, edited templates, added/removed workstation packages in any Brewfile, and modified scripts. Project-level Devbox changes are applied when you enter that project or run `devbox install` there. VS Code settings and extensions are handled by VS Code Settings Sync, not this repo.

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
bash ~/Dev/Personal/dotfiles/install.sh
```

It'll detect your existing config in Phase A and ask whether to re-use prior answers; say no to get the full multi-select again.

### How the invalidation rules work

Knowing what triggers what makes the upgrade story less mysterious:

| You edit / pull… | Triggers on next `chezmoi apply` |
|---|---|
| Any file under `dot_*` or `private_dot_*` | chezmoi writes it to `$HOME` |
| A `.tmpl` template | chezmoi re-renders it against your current `[data]` block |
| `Brewfile` or `brewfiles/Brewfile.*` | `run_onchange_after_02-brew-bundle.sh` re-fires (hash comment caught it) |
| `.chezmoi.toml.tmpl` itself | **nothing automatic** — you must run `chezmoi init` (or `chezreinit`) to re-render `~/.config/chezmoi/chezmoi.toml`. This is the only common case where `chezup` alone is insufficient |
| `scripts/macos-defaults.sh` | nothing — it's `run_once_after`. Manually run `macos-defaults` (the alias) to re-apply |

If you forget which path you're on, `chezdiff` shows you everything pending at once: chezmoi's dotfile diff, brew-bundle drift across every tracked Brewfile, and which `run_*` scripts would re-fire. It's the "what would chezup actually do" preview.

### Cleaning up packages from features you've turned off

Disabling a feature toggle stops that Brewfile from being re-applied, but does **not** uninstall the packages it pulled in — intentional, so you don't lose tools you might still use. To actually remove the current mac-apps feature packages:

```sh
brew bundle cleanup --force --file=~/Dev/Personal/dotfiles/brewfiles/Brewfile.mac-apps
```

`chezaudit` (alias) shows you packages currently installed that aren't tracked in any Brewfile, which is useful when you've manually `brew install`ed something and want to decide whether to promote it into a workstation Brewfile, move it into a project Devbox, or remove it.

### What to do after a long absence (machine sitting idle for weeks)

```sh
chezreinit         # pull + init + apply — handles data-model drift in one shot
chezbump           # brew update/upgrade + devbox global update
chezdoctor         # full health check — surfaces anything that broke while you were away
```
