# Homebrew packages

Homebrew owns every global CLI and GUI app; mise owns language runtimes. The
split matters — reaching for `npm -g` or `pip --user` puts a tool somewhere
neither of them can reconcile.

## Tiers

Packages are declared across five Brewfiles, and which ones apply to a machine
depends on its profile and enabled modules:

| Tier | File | Applies |
|---|---|---|
| Core | `Brewfile` | Always |
| Module | `Brewfile.mac-apps`, `Brewfile.apple-dev` | When that module is on |
| Profile | `Brewfile.personal`, `Brewfile.work` | To that profile |

The mapping lives in [`src/.chezmoidata/brew.toml`](../../src/.chezmoidata/brew.toml)
as repo-root-relative paths, which the hooks join with
`{{ .chezmoi.workingTree }}`.

## Why install and removal must resolve the same set

`lib/tiers.sh:brew_active_files` answers "which Brewfiles apply here", and both
directions go through it: the apply hook installs from that set, `chezmirror`
offers everything *outside* it for removal, and `chezdoctor` reports drift
against it.

They used to disagree. The install side was profile- and module-gated while the
removal side globbed every `Brewfile.*` that existed, so `chezdoctor` called a
work-only cask "untracked" on a personal machine. One resolver is what stops
that, and `tests/doctor.bats` pins the regression.

A consequence worth knowing: moving a package to the *other* profile's tier makes
it removable here. The other profile's Brewfile does not keep it alive, which is
the same thing deleting it would do.

The removal side fails **closed** — if the tier set cannot be resolved it offers
nothing rather than guessing wider.

## The progress bar is real

`lib/progress.sh` derives its denominator by counting entries in the Brewfiles
actually being installed, then ticks on Homebrew's own output. It is not a
timer pretending to be progress. It also parks itself when Homebrew asks for a
password — a bar advancing over a hidden prompt is how an install appears to
hang.

## Tap trust

Homebrew 6.0 requires third-party taps to be trusted before use. `lib/homebrew.sh`
derives the declared taps from the Brewfiles themselves — explicit `tap` lines
plus any fully-qualified `org/name/formula` — and trusts them before the bundle
runs, so a fresh Mac does not stop halfway on a prompt nobody is there to answer.

It also pins `XDG_CONFIG_HOME` so the trust store lands in `~/.config/homebrew`
rather than `~/.homebrew`.

## Gotchas

`homebrew_install` is duplicated inline in the repo's root `install.sh`. That is
deliberate and commented at both ends: `install.sh` runs via `curl | bash` before
the repo exists, so it cannot source anything.

`chezmirror` and `chezbump` still live in `src/dot_config/zsh/dot_zshrc.tmpl` as
inline zsh. They move here next; the zshrc sources `lib/tiers.sh` directly in the
meantime, which is why that file must stay POSIX-safe for both bash and zsh.
