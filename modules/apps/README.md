# apps

Repo: [dotfiles](../../README.md) · The module contract:
[docs/modules.md](../../docs/modules.md)

GUI apps and fonts, as Homebrew casks. No `home/`, no `apply.sh`: a cask is
the whole installation, and `brew bundle` does it.

## What belongs here

Things with a window or a menu bar item. CLIs go in `dev-cli`.

A cask whose absence would **break another module's shipped config** ships from
that module instead — `1password` from `ssh` and `git`, the Nerd Font from
`zsh` and `cmux`. Enabling `apps` must never be the undeclared requirement that
makes a different module work, and `module.toml` has no field to say so. A cask
another module merely *prefers* stays here: `git` and `zsh` both fall back in
the open when VS Code is absent.

## The one check

`brew bundle` is satisfied the moment a cask lands in `/Applications`, and for
a menu bar app that is half an installation. Raycast that was never opened has
no hotkey; Stats that was never opened has no menu bar item. Nothing else in
the repo can see it — the cask is present, so `brew_missing` is green and the
orphan scan has nothing to say.

`data/launch.tsv` lists the apps that are useless until opened, and `doctor.sh`
reports the ones that never were:

```
  ▲ Raycast      installed but never opened -- no launcher, and no hotkey to reach it
    open -a Raycast, then turn on its own "launch at login"
```

Four rules keep it from becoming a permanently yellow line:

- **Only apps that do nothing until running.** Chrome and VS Code are opened
  when you want them; they are not listed.
- **A row is silent when the app is not installed.** Dropping the cask from
  `Brewfile` is the escape hatch for an app you decided against. Column 2 names
  that cask, and `tests/contract.bats` holds the two files together.
- **Column 4 finishes the sentence, and carries no article.** `doctor.sh` owns
  the words around it; two files owning half a sentence each is how you get
  "no the launcher". `tests/apps.bats` holds every row to it.
- **First launch, not "running now".** macOS writes the preferences domain the
  first time an app opens and never takes it back, so quitting Stats for an
  afternoon changes nothing. It is weaker evidence than the login item, which
  is what you actually want set — but that lives in a database only root reads,
  and a check that needs `sudo` is a check nobody runs.

The default browser is **not** checked here. It is macOS system state rather
than anything this module installs, so it lives with FileVault and the firewall
in [`macos-defaults`](../macos-defaults/README.md).
