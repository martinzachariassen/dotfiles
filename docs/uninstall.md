# Uninstalling

```sh
bash uninstall.sh --dry-run    # print every intended change, make none
bash uninstall.sh              # do it
```

The counterpart to `install.sh` rather than a sixth `dot` verb: `bin/dot` is
capped at five, and the most destructive thing the repo can do does not belong
behind the command you type every day. The interactive run shows you the
`--dry-run` preview and then asks you to type `remove`. The preview *is* this
script under `--dry-run`, not a hand-written summary that could drift from it.

A full reset — module `remove.sh` hooks, links, generated files, config, logs,
applications, Homebrew, and finally the checkout. **Xcode Command Line Tools
are left installed**, being macOS developer plumbing rather than something this
repo chose for you.

[Homebrew goes in its entirety](#homebrew-goes-in-its-entirety) ·
[Casks go first](#casks-go-first-while-homebrew-still-works) ·
[Three things it will not do](#three-things-it-will-not-do) ·
[Undoing one module instead](#undoing-one-module-instead)

## Homebrew goes in its entirety

Not just the packages this repo named. Homebrew's uninstaller removes the whole
Cellar and Caskroom and keeps no record of who asked for what. The preview
counts this out rather than describing it, because the sentence version reads
as "the packages this repo installed" and that is the one misreading that
matters:

```
── Homebrew and the repo ───────────────────────────────────────────────────
  → uninstall Homebrew and all 109 formulae it manages
  ▲ 80 of those are named by no Brewfile here -- they go too
  → remove       /Users/you/Developer/personal/dotfiles
```

## Casks go first, while Homebrew still works

Homebrew *moves* a cask's `.app` into `/Applications`, and its own uninstaller
deletes the prefix and nothing outside it — left to itself it would strand
every GUI app on the machine, still installed with nothing left that can remove
them. `brew services` leaks the same way, so services are stopped first. Each
cask goes with `--zap`, which takes its application support, preferences and
caches too.

If a cask *fails* to uninstall, the run stops before Homebrew: destroying the
only tool that could remove an app you just failed to remove is exactly the
leftover this step prevents.

The last two steps remove Homebrew (which owns the running bash) and the
checkout (which holds the running script), so they hand off to a throwaway
script under `/bin/bash` — the one shell still there once Homebrew is gone.

## Three things it will not do

- **It never deletes your backup tree.** `~/.local/state/dotfiles/backups/`
  holds real files an earlier `apply` moved aside, and nothing else has a copy.
  It is reported as kept, and deleting it is yours to do.
- **It never deletes a real file it did not put there.** Symlinks into the
  repo, the two generated files it can prove it wrote, and the paths that are
  the repo's own by definition. The directories then go with `rmdir`, not
  `rm -rf`, so a file some other tool left keeps it alive and gets reported.
- **It cannot undo macOS defaults.** It reports the domains instead — and only
  when at least one is still in force, because it runs every module's
  `remove.sh`, enabled or not, and a machine that never turned
  [that module](../modules/macos-defaults/README.md) on must not be told its
  preferences were changed.

## Undoing one module instead

`dot remove <module>` is the reversible version, and `dot add` puts it back.
See [configuration.md](configuration.md#enabling-and-disabling).
