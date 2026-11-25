# Changelog

All notable changes to this repo. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). Below 1.0.0 a minor bump may change
behaviour.

## [0.2.0] - 2026-11-24

### Added

- `dot apply --pull` fast-forwards the checkout and re-runs the pulled `dot`,
  refusing over uncommitted changes. A dry run announces the pull and never
  calls git.
- The `ios` module for iPhone and Apple Watch apps in VS Code: SweetPad, the
  Swift extension, XcodeGen, SwiftLint and xcbeautify, the iOS and watchOS
  simulators once Xcode is selected, and the `swift-lsp` Claude Code plugin.
- `dot doctor` warns when the checkout is behind or has diverged from its
  upstream, and a comparison git could not make is a warning, never green.
  `dot doctor --fetch` runs `git fetch` first and carries on with a warning
  when the remote cannot be reached.
- A mise lockfile for `dev-cli`: runtimes install with `mise install --locked`,
  so two machines built a month apart get the same versions, and a tool
  missing from the lock fails instead of resolving on the spot. Go is now one
  of the runtimes, and golangci-lint tracks latest.
- Apps: ZenNotes, Discord (in place of Thaw) and KeepingYouAwake.
- Claude Code module: the `review-fix`, `ci-fix`, `release` and `tidy` skills,
  the `check-runner` agent, a `git-guard` hook that denies force-pushes, hook
  skipping and pushes to the default branch, and a filled-in global
  `CLAUDE.md`. `ship` and `readme` are upgraded, and `ship`, `review-fix` and
  `ci-fix` keep a PR's title and description true after every push.

### Changed

- A run is quieter and easier to read. Modules that have nothing to do collapse
  to one line with their time; a group opens at the first change or problem. A
  run ends on a count of changes by kind, and the checks after an apply show
  only what failed.
- While brew installs, a live line shows a bar, percent, size, speed and time
  left. It is drawn only with a terminal attached and never reaches the
  transcript. `DOT_PROGRESS=0` turns it off.
- Apply hooks announce a change only when there is one. `macos-defaults` writes
  only drifted keys and restarts only the apps whose domain changed; `dev-cli`
  runs `mise install` only when a pinned runtime is missing.
- `dot --help` explains the markers, lists the modules and which are enabled,
  and describes the exit status, the environment and the files.
- The README is restyled around a banner, a quick start and a real `dot apply`
  sample. `CLAUDE.md` is now the one rulebook for the repo; the reasoning lives
  in `docs/`.
- The ssh notes moved into `modules/ssh/README.md`.
- Comments are cut to the landmines: code that is right for a reason the next
  reader would undo.
- `core/doctor.sh` has its own test suite, and `statusline.sh` is linted and
  tested.
- The starship prompt no longer substitutes icons for directory names.

### Removed

- `macos-defaults`: the `touch_id_sudo` setting and its doctor check.
- `dev-cli`: the `firebase-cli` package and its doctor row.
- Chrome from the `apps` module.
- Claude Code module: the `dotfiles-test` skill.

### Fixed

- `~/.config/op` is kept at mode 700. `op` refuses a broader mode and fails
  every `op://` reference; `apply` now sets it and `doctor` warns while it is
  wrong.
- `dev-cli` checks sign-ins even when `mise` is missing.
- `macos-defaults` names everything it writes and no longer prints `ok` after a
  refused `dock_tilesize`.
- `brew_unmanaged` matches tap formulae by their full name, so a tap formula a
  Brewfile names is no longer reported unmanaged.
- `dot doctor` finds Xcode 27 simulator runtimes, which are mounted as
  cryptexes instead of living under `/Library/Developer/CoreSimulator`.
- Removing a module that never ran, such as `ios`, stays silent.
- The test sandbox points `xcode-select`, CoreSimulator and `claude` at
  stand-ins, so `uninstall.bats` no longer reads the real Xcode.
- CI uses `actions/checkout` v7.0.1, pinned by SHA.

## [0.1.2] - 2026-09-22

### Fixed

- The install wizard shows every step's prompt as it goes, with a heartbeat
  while a module installs quietly.

## [0.1.1] - 2026-09-21

### Added

- Fresh-machine doctor checks, 1Password-backed API keys and verifiable commit
  signing.

## [0.1.0] - 2026-09-12

### Added

- The first tagged release of the Mac setup: the `install.sh` bootstrap, the
  `dot` verbs, eleven modules and the test suite that holds their contract.

[0.2.0]: https://github.com/martinzachariassen/dotfiles/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/martinzachariassen/dotfiles/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/martinzachariassen/dotfiles/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/martinzachariassen/dotfiles/releases/tag/v0.1.0
