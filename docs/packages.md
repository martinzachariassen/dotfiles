# Packages & modules

What gets installed is chosen by one answer you give the [wizard](#the-wizard) —
your **optional modules** — plus whatever this Mac has adopted locally. Both feed
a single data model in [`src/.chezmoidata/`](../src/.chezmoidata) that the apply
hooks and the doctor report read, so the mapping is never restated in more than
one place.

## Package tiers

Packages are layered Brewfiles under [`features/brew/`](../features/brew). The active set
is the core file plus whatever your modules add:

| Tier | File | Installed when |
|---|---|---|
| **Core** | [`Brewfile`](../features/brew/Brewfile) | Always. The smallest set that makes the documented shell experience work. |
| **Module** | `Brewfile.mac-apps`, `Brewfile.apple-dev` | The matching module is selected (`macApps` → GUI + AI apps; `appleDev` → Swift/iOS toolchain). |
| **Machine-local** | `~/.config/chez/Brewfile.local` | Always, on the one Mac that has it. Outside the repo, never committed — see [adopt](../features/adopt/README.md). |

There is no per-machine-kind tier. v1.0 retired the `profile` enum along with
`Brewfile.personal` and `Brewfile.work`; the cloud/Kubernetes/IaC stack the work
tier used to declare now lives in the machine-local overlay of the one Mac that
wants it, moved there automatically by
[`migrate-work-profile.sh`](../features/brew/migrate-work-profile.sh) without
uninstalling anything.

The module→file mapping lives in
[`src/.chezmoidata/brew.toml`](../src/.chezmoidata/brew.toml) — the
single source of truth. The `run_after_02-brew-bundle` hook reads the active
set and runs `brew bundle --no-upgrade`, converging *presence*, not freshness.
See [lifecycle.md](lifecycle.md#where-each-piece-lives).

The machine-local tier is the answer to "this package is mine, on purpose". It
is read last, so it can only ever *add* to the declared set, and it makes the
package declared in the full sense: installed by the apply, spared by
`chez mirror`, not reported by `chez doctor`. `chez adopt --local <package>`
writes to it; deleting the line hands the package straight back.

### Mac App Store apps (mas)

App Store apps are declared with [`mas`](https://github.com/mas-cli/mas) in the
`macApps` tier ([`Brewfile.mac-apps`](../features/brew/Brewfile.mac-apps)) so
`brew bundle` reproduces them on a fresh Mac. Each line is `mas "Name", id:
NNN`; you must be signed in to the App Store before an apply installs them.

This is **install/reproducibility only** — it does *not* make App Store apps
auto-prune, on purpose. `brew bundle cleanup` (the engine behind
[`chez mirror`](commands.md)) never uninstalls `mas` apps, so dropping a `mas`
line does **not** remove the app; that stays a manual `mas uninstall <id>`.
This matches the repo's [removal-is-manual model](lifecycle.md) — an apply
only adds.

Nothing is declared by default: `mas` can't be queried from CI, and
speculative IDs would install unwanted apps. Populate the list from your own
machine — run `mas list` on a signed-in Mac and paste the apps you want
reproduced into `Brewfile.mac-apps` under the `mas` section.

## Optional modules

A multi-select of add-ons, catalogued in
[`src/.chezmoidata/modules.toml`](../src/.chezmoidata/modules.toml). Templates
gate on membership with sprig `has`, e.g.
`{{ if has "theme" .modules }}…{{ end }}`.

| Module | What it adds |
|---|---|
| `macApps` | GUI and AI apps (Raycast, Chrome, Claude) plus `mas` for App Store apps (see [above](#mac-app-store-apps-mas)). |
| `macosDefaults` | macOS system defaults (needs sudo) — see [macos.md](macos.md). |
| `cloudAuth` | Cloud CLIs and auth walkthrough (gh, az, gcloud, op). |
| `claudePersona` | Claude global defaults at `~/.config/claude/CLAUDE.md` (see [ai.md](ai.md)). |
| `theme` | Catppuccin Mocha across terminal and editor (see [terminal.md](terminal.md)). |
| `locale` | Norwegian locale (cSpell `nb`, bokmål dictionary). |
| `jvmStack` | JVM runtimes via mise (Temurin, Kotlin, Maven, Gradle — see [shell.md](shell.md#runtimes-mise)). |
| `appleDev` | Swift/iOS toolchain (SwiftLint, SwiftFormat, xcbeautify, fastlane, SF Symbols). Pre-ticked by default. Installs the *tooling* only — Xcode.app, its licence and an iOS simulator runtime come from [`chez xcode`](commands.md#advanced--occasional-helpers), which needs an Apple ID and so can't run during an apply. The `xcodes` CLI is **not** a Brewfile entry: the only tap formula builds from source and that build needs a full Xcode.app, which is the thing it exists to install, so it could never succeed on a fresh Mac. `chez xcode` fetches upstream's signed prebuilt binary into `~/.local/bin` instead, verified against the sha256 pinned in [`src/.chezmoidata/xcode.toml`](../src/.chezmoidata/xcode.toml). |

The set the wizard pre-ticks lives in the `[recommended]` table of
`modules.toml` — one list, the same on every Mac. It replaced three tables keyed
by profile: a base set, an inherit flag and a per-kind extra list, all to decide
which boxes started ticked for something you could immediately untick.

That table **must** mirror the `$defaults` list in
[`.chezmoi.toml.tmpl`](../src/.chezmoi.toml.tmpl) — the config template
renders before `.chezmoidata` loads, so it can't read the table and restates
the list literally. `tests/data-model.bats` enforces the match so the two
never drift.

## The wizard

The setup questions (`name`, `email`, `signingMode`, and the `modules`
multi-select) are chezmoi's own `init` prompt data, defined in
[`.chezmoi.toml.tmpl`](../src/.chezmoi.toml.tmpl) with `*Once` semantics so
re-running is idempotent. But chezmoi renders those prompts as an interactive
TUI picker that is unreliable under `curl | bash` and some terminals (it can
fail to register navigation and just confirm the default). So
[`features/setup/cli.sh`](../features/setup/cli.sh) is the front-end: it asks
each question with plain `read` from `/dev/tty` and passes the answers to
`chezmoi init --apply` via its `--promptString/-Choice/-Multichoice` flags —
no TUI.

The prompts degrade across three tiers to fit the terminal:

- **gum** pickers when `gum` is installed (any re-run after the first
  install), with your current selection pre-checked;
- a **pure-bash arrow/space picker** when there's no gum yet but the terminal
  is capable (the first-boot case — it also accepts number keys, so it works
  even if arrows don't register); and
- the **numbered menu** on a dumb/non-ANSI terminal.

`WIZARD_NO_GUM=1` skips the first tier, `WIZARD_NO_TUI=1` the first two.

`bash features/setup/cli.sh` (or `chez setup`) is the "change the setup" path;
`chez setup --reset` also replays first-time setup. See
[commands.md](commands.md#changing-your-setup) for how the two modes differ.

## Adding a package

- **A tool everyone gets** → add it to the core [`Brewfile`](../features/brew/Brewfile),
  alphabetically within its section.
- **Module-specific** → add it to the matching layer file. If it's a new module,
  add the catalog entry to `modules.toml`, its Brewfile mapping to `brew.toml`,
  and mirror the catalog into `.chezmoi.toml.tmpl`.
- **Only this Mac** → `chez adopt --local <package>`. It goes in
  `~/.config/chez/Brewfile.local`, outside the repo, and is declared in every
  sense that matters — installed by the apply, spared by the removal verbs.

CI resolves every Homebrew name on macOS (`scripts/ci/brew-resolve.sh`), so a
typo'd formula fails the build; `brew-check-modules.sh` runs alongside it as
an advisory-only bundle check. Module wiring itself (every `brew.toml`
entry pointing at a real Brewfile) is enforced by `tests/data-model.bats`.
See [development.md](development.md).
