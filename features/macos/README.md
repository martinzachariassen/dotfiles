# macOS system defaults

One idempotent pass of `defaults write` over keyboard, trackpad, Finder, Dock,
screenshots, security and developer settings, plus enabling Touch ID for `sudo`.
Everything it sets is catalogued in [docs/macos.md](../../docs/macos.md); this
explains when it runs and why it is shaped the way it is.

## When it runs

Two ways, and they share one script. `run_onchange_after_04-macos-defaults`
applies it during a `chezup`/`chezapply` when the `macosDefaults` module is on
and the script's contents have changed — `run_onchange_` rather than `run_once_`
because `run_once_` would silently ignore every later edit. The `macos-defaults`
verb runs the same file by hand, which is what you want after resetting a
preference pane, or on a machine where the module is off.

The verb is deliberately *not* module-gated even though the hook is. The module
decides whether an apply touches system settings; it should not decide whether
you can run them yourself.

## Why it cannot abort the apply

The hook invokes the script inside an `if`, never bare under `set -e`, and
reports failure rather than propagating it. Hooks 05 and 99 run after this one,
and 99 prints the "Next moves" block — `chezsign`, `bootstrap-auth`,
`chezdoctor` — that a fresh Mac depends on. A failed defaults pass must never
cost the user those instructions. `tests/chezmoi-scripts.bats` pins that shape.

## sudo, and the two ways it can hang

chezmoi runs scripts with stdin closed, so a `sudo` prompt inside this script
would hang forever with nothing on screen. The hook reattaches a controlling
terminal first via `core/tty.sh` and skips cleanly when there is none.

Separately, `run_before_00-sudo-cache` has already authenticated and is keeping
the timestamp warm for the whole apply. The hook passes
`DOTFILES_SUDO_KEPT_WARM=1` so `cli.sh` does not spawn a second, redundant
keeper. Run the verb by hand and no such variable is set, so it starts its own.

## What stays outside this feature

`core/sudo.sh` and `core/tty.sh` are shared with the Homebrew bundle hook, so
they belong to `core/`, not here. `run_before_00-sudo-cache` serves the whole
apply for the same reason. `tests/sudo-prompts.bats` spans `install.sh`, two
hooks and this script — it pins the rule that every password prompt explains
itself before appearing, which is not one feature's property.
