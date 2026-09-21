# macos-defaults

Repo: [dotfiles](../../README.md) · The module contract:
[docs/modules.md](../../docs/modules.md)

macOS system preferences — Dock, Finder, trackpad, keyboard, text substitution,
screenshots, and the locale units. Imperative and idempotent, and the only
*tool* module that links no files at all: none of this is a file, so it has no
`home/` and no Brewfile either.

Nothing here needs root.

## One table, three readers

```mermaid
flowchart TD
  T["data/defaults.tsv<br/>domain · key · type · value · why"]
  T --> A["apply.sh — defaults write, every row"]
  T --> D["doctor.sh — defaults read, compare every row"]
  T --> R["remove.sh — column 1 → the domains it warns about"]
```

The writes are a data file, not shell literals, and that buys more than fewer
lines. A list a hook types out is a claim nothing checks, and the cost per line
is what makes a hook *sample* instead of check. Cut from the file, the list
cannot go stale and the sample becomes the whole table — so `doctor.sh` compares
every key, and `remove.sh` cannot name a domain `apply.sh` no longer writes.

`tests/contract.bats` pins all three to the same `data=` line, and separately
forbids `remove.sh` from naming a domain by hand.

### Units are written, not inherited

The locale rows — 24-hour clock, metric, Celsius — are values macOS would
otherwise derive from the region the installer was answered with. On a machine
set up as Norwegian they change nothing; writing them anyway is what makes the
answer a property of *this repo* rather than of an installer dialog nobody
remembers. That is the same reason every other row is here: a preference that
depends on how the machine was set up is one a rebuild can get wrong.

Column 3 is the `defaults` type, so `apply.sh` writes with `-$type`. Both
readers have to undo it the same way, because `defaults read` prints a bool as
`1`/`0` and never as `true`/`false` — a test holds that mapping identical in the
two hooks.

## What is not in the table

A value that needs a config setting, or validation, stays in `apply.sh` where it
can be refused. The file holds only what a reader could not argue with.

| Setting | Default | Notes |
|---|---|---|
| `dock_autohide` | `true` | normalised to a literal `true`/`false` |
| `dock_tilesize` | `48` | must be a positive integer — `defaults -int` stores non-numeric as `0`, and tilesize `0` is a Dock with no icons |
| `screenshot_dir` | `Pictures/Screenshots` | relative to `$HOME` unless absolute; a leading `~` is expanded, not taken literally |
| `touch_id_sudo` | `true` | not written at all — only *checked*; see below |
| `macos_auto_update` | `false` | not written at all — only *checked*; see below |
| `browser` | `"com.google.chrome"` | not written at all — only *checked*; `""` silences it |

```toml
[settings.macos-defaults]
dock_autohide     = true
dock_tilesize     = 48
screenshot_dir    = "Pictures/Screenshots"
touch_id_sudo     = true
macos_auto_update = false
browser           = "com.google.chrome"
```

A bad value is a `fail`, not a `die`: one wrong field must not cost the rest of
the run.

## Applying

Dock, Finder, SystemUIServer and WindowManager read their preferences at launch
only, so `apply.sh` restarts them. `NSGlobalDomain` cannot be restarted —
keyboard and text-substitution changes need a **log out and back in**, which
both the dry run and the real run say in the same words.

That line is `dim`, not `warn`. It is true of every run that reaches it, and as
a warning it would exit `DOT_STATUS_WARN` every time and `dot apply` could never
reach "Done".

`doctor.sh` warns rather than fails on drift: an OS update or a Settings pane
reverting a key is not a broken install. But it is otherwise invisible — the
only symptom is a Mac that behaves slightly wrong — which is why every row is
checked.

## What it reports and cannot write

FileVault, the application firewall, Touch ID for `sudo`, the software update
switches and the default browser are not `defaults` keys this module may
write. Each needs root or a GUI confirmation, so `apply.sh` cannot set them —
and they are deliberately **not** in `data/defaults.tsv`, which is the list of
what this module writes and what `remove.sh` derives its domains from. A row
there would make `apply.sh` run `defaults write` against something that is not
a preference at all.

`doctor.sh` reports them anyway, because this is the module for macOS system
state and a Mac with the firewall off is otherwise something nothing in this
repo ever looks at. Reading all three needs no root and no unlock:

| Checked with | Green when |
|---|---|
| `fdesetup status` | `FileVault is On.` |
| `socketfilterfw --getglobalstate` | `State = 1` or `2` — 2 is on *and* blocking all incoming |
| `/etc/pam.d/sudo_local` | it holds an **uncommented** `pam_tid.so` auth line |

The last one is the subtle one. macOS ships `sudo_local.template` with the
`pam_tid` line commented out, so copying the template and changing nothing is
the most likely half-done state there is — and a check for the file alone would
call it finished.

Touch ID is also the only one of the three with a setting. FileVault and the
firewall are baselines; wanting `sudo` to keep asking for a password is a
taste, and without `touch_id_sudo = false` a machine that holds it would stay
yellow forever — which says exactly as little as a machine that is always
green.

A tool that answers nothing is a **warning**, never silence: a question that
could not be asked is not a healthy answer, the same three-state rule
`brew_missing` exists to keep.

## Software update, split six ways

macOS keeps automatic updates in six keys under `/Library/Preferences`, and
they are reported as two groups rather than one, because they are not one
decision:

| Key | Domain | Wanted |
|---|---|---|
| `AutomaticCheckEnabled` | `com.apple.SoftwareUpdate` | on |
| `AutomaticDownload` | `com.apple.SoftwareUpdate` | on |
| `CriticalUpdateInstall` | `com.apple.SoftwareUpdate` | on — security responses |
| `ConfigDataInstall` | `com.apple.SoftwareUpdate` | on — XProtect and system data |
| `AutoUpdate` | `com.apple.commerce` | on — App Store apps |
| `AutomaticallyInstallMacOSUpdates` | `com.apple.SoftwareUpdate` | `macos_auto_update`, default **off** |

The last one is the reason the split exists. It does not mean "security
patches"; it means macOS installs *whole versions* on its own, major ones
included. Left on, a Mac can move to the next major release unasked — and the
only way back is erasing the disk, while the fix for the surprise is a switch
that also stops the patches. Off, the five above keep every automatic update
this machine actually wants, and the version bump becomes a button you press.

Reading `/Library/Preferences` needs no root; writing it does, which is why
this is a report and names the command:

```
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate \
  AutomaticallyInstallMacOSUpdates -bool false
```

**A key macOS never wrote is not "off".** All six ship on, so a Mac whose
owner never opened the pane has no key at all — calling that off would send
you to a checkbox that is already ticked.

That holds for the sixth row as much as the first five, and it is the one
place getting it backwards costs something: a fresh Mac nobody has touched
**is** set to install whole versions unasked. Reading its missing key as "off"
would make the default answer green on exactly the machine the row exists for.
Only a literal `0` is off.

**And a key that could not be read is neither.** `defaults read` exits
non-zero for a key that was never written and for a domain this process cannot
read, so the check asks the *domain* as well: one that answers and holds no
such key is a machine at its shipped default and stays green, and one that
does not answer at all is a question that could not be asked, which warns.
Collapsing the two would make all six switches green on a Mac nobody could ask
— the three-state rule again, and the one place in this module where getting it
wrong produces a clean bill of health rather than a wrong line.

## The default browser

`apps` installs Chrome; nothing makes it the browser. Every link opens in
Safari until someone clicks through a confirmation sheet, and no script may
click it — that sheet is the whole security property.

So it is reported, from the LaunchServices handler for `https`, against the
`browser` setting. The setting is also the escape hatch: `browser = ""` says
nothing at all, which is what a Mac that wants Safari sets.

The same three states apply, and here the middle one is the common case: a Mac
with **no** handler list has never had a handler overridden, which is Safari
and is exactly what the check wants to report. A LaunchServices database that
*fails* to read is not that, and says so instead of naming a browser.

It lives here rather than in `apps` because it is macOS system state, not
something that module installs — the same reason FileVault is here.

The paths are inputs — `DOT_SOCKETFILTERFW`, `DOT_SUDO_LOCAL` and the two
software-update domains, `DOT_SOFTWAREUPDATE_PREFS` and `DOT_COMMERCE_PREFS` —
because otherwise the branch a test needs is the one the machine running it
never takes. A test may not write to `/Library/Preferences` at all, which is
what leaves the unreadable-domain branch unreachable without them.

## This module cannot be undone

`apply.sh` never read the old values, so they exist nowhere. `defaults delete`
would give you Apple's factory setting, not what you had. Making it reversible
means recording state at apply time, and this repo derives rather than records.

So `remove.sh` deletes nothing. It prints the domains that were written to and
says plainly that they cannot be put back — and only when at least one row of
the table is **still in force**, because `uninstall.sh` runs every module's
`remove.sh`, enabled or not, and a machine that never turned this one on must
not be told its preferences were changed.

Putting a value back is manual, in System Settings or with `defaults write`. The
domains are listed for you; the values from before are gone.
