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
directions go through it: the apply hook installs from that set, `chez mirror`
offers everything *outside* it for removal, and `chez doctor` reports drift
against it.

They used to disagree. The install side was profile- and module-gated while the
removal side globbed every `Brewfile.*` that existed, so `chez doctor` called a
work-only cask "untracked" on a personal machine. One resolver is what stops
that, and `tests/doctor.bats` pins the regression.

A consequence worth knowing: moving a package to the *other* profile's tier makes
it removable here. The other profile's Brewfile does not keep it alive, which is
the same thing deleting it would do.

The removal side fails **closed** — if the tier set cannot be resolved it offers
nothing rather than guessing wider.

## Comparing installed against declared

`chez doctor` answers "what is installed that no active tier declares" itself,
rather than through `brew bundle cleanup` the way `chez mirror` and `chez
status` do — that path calls `brew trust --tap`, and doctor is read-only. Two
rules keep the cheap comparison honest, both in
`lib/tiers.sh:brew_untracked_of_kind`:

- **Both sides are normalised, never just one.** `brew leaves` prints a tap
  formula qualified (`hashicorp/tap/terraform`) and tap owners carry capitals
  the installed name drops (`Azure/kubelogin` → `azure/…`), while a Brewfile may
  declare either spelling. `brew_bare_names` reduces both to the bare,
  lowercased name. Stripping only the Brewfile side was a real bug: every
  tap-installed package read as untracked on every run.
- **Formulae and casks are compared separately.** They are distinct Homebrew
  namespaces and some names live in both — docker ships as a formula *and* as a
  cask — so a merged set would let a declared cask vouch for an undeclared
  formula. The installed side is `brew leaves` for formulae (dependencies are
  the orphan check's business) and `brew list --cask` for casks, which have no
  leaf/dependency distinction.

`tests/tiers.bats` pins both, and `tests/doctor.bats` pins that the fragment
keeps reading through the shared helper instead of re-parsing Brewfiles.

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

`chez mirror` and `chez bump` are `mirror.sh` and `bump.sh` here now. They were
~240 lines of zsh inside `dot_zshrc.tmpl`, where the shellcheck and shfmt globs
could not reach them and eight test files got at them by `sed`-ing function
bodies out of a Go template. The zshrc keeps one-line wrappers.

One wrapper survives in the template: `_chez_brew_removals`. `chez apply` and
`chez status` still live there and still need the removal set, so it sources
`lib/removals.sh` and calls into it rather than keeping a second copy. It goes
when those two verbs move. That is also why `lib/removals.sh` and `lib/tiers.sh`
must stay POSIX-safe for both bash and zsh.
