# Packages, profiles & modules

What gets installed is chosen by two answers you give the [wizard](#the-wizard):
your **profile** and your **optional modules**. Both feed a single data model in
[`src/.chezmoidata/`](../src/.chezmoidata) that the apply hooks and the doctor
report read, so the mapping is never restated in more than one place.

## Package tiers

Packages are layered Brewfiles under [`packages/`](../packages). The active set
is the core file plus whatever your profile and modules add:

| Tier | File | Installed when |
|---|---|---|
| **Core** | [`Brewfile`](../packages/Brewfile) | Always. The smallest set that makes the documented shell experience work. |
| **Profile** | `Brewfile.personal` / `Brewfile.work` | Your profile matches. `work` adds the cloud/Kubernetes/IaC CLIs (az, gcloud, kubectl, kubectx, kubelogin, terraform, helm, minikube) and work apps (M365, Teams, Slack). |
| **Module** | `Brewfile.mac-apps`, `Brewfile.apple-dev` | The matching module is selected (`macApps` → GUI + AI apps; `appleDev` → Swift/iOS toolchain). |

The profile→file and module→file mappings live in
[`src/.chezmoidata/packages.toml`](../src/.chezmoidata/packages.toml) — the
single source of truth. The `run_after_02-brew-bundle` hook reads the active
set and runs `brew bundle --no-upgrade`, converging *presence*, not freshness.
See [lifecycle.md](lifecycle.md#where-each-piece-lives).

### Mac App Store apps (mas)

App Store apps are declared with [`mas`](https://github.com/mas-cli/mas) in the
`macApps` tier ([`Brewfile.mac-apps`](../packages/Brewfile.mac-apps)) so
`brew bundle` reproduces them on a fresh Mac. Each line is `mas "Name", id:
NNN`; you must be signed in to the App Store before an apply installs them.

This is **install/reproducibility only** — it does *not* make App Store apps
auto-prune, on purpose. `brew bundle cleanup` (the engine behind
[`chezmirror`](commands.md)) never uninstalls `mas` apps, so dropping a `mas`
line does **not** remove the app; that stays a manual `mas uninstall <id>`.
This matches the repo's [removal-is-manual model](lifecycle.md) — an apply
only adds.

Nothing is declared by default: `mas` can't be queried from CI, and
speculative IDs would install unwanted apps. Populate the list from your own
machine — run `mas list` on a signed-in Mac and paste the apps you want
reproduced into `Brewfile.mac-apps` under the `mas` section.

## Profiles

One of `personal`, `work`, or `minimal`, chosen at setup. A profile selects its
Brewfile layer and pre-checks a default set of modules (below).

## Optional modules

A multi-select of add-ons, catalogued in
[`src/.chezmoidata/modules.toml`](../src/.chezmoidata/modules.toml). Templates
gate on membership with sprig `has`, e.g.
`{{ if has "theme" .modules }}…{{ end }}`.

| Module | What it adds |
|---|---|
| `macApps` | GUI and AI apps (Raycast, Chrome, Claude, Ollama) plus `mas` for App Store apps (see [above](#mac-app-store-apps-mas)). |
| `macosDefaults` | macOS system defaults (needs sudo) — see [macos.md](macos.md). |
| `cloudAuth` | Cloud CLIs and auth walkthrough (gh, az, gcloud, op). |
| `claudePersona` | Claude global defaults at `~/.config/claude/CLAUDE.md` (see [ai.md](ai.md)). |
| `theme` | Catppuccin Frappé across terminal and editor (see [terminal.md](terminal.md)). |
| `locale` | Norwegian locale (cSpell `nb`, bokmål dictionary). |
| `jvmStack` | JVM runtimes via mise (Temurin, Kotlin, Maven, Gradle — see [shell.md](shell.md#runtimes-mise)). |
| `appleDev` | Swift/iOS toolchain (SwiftLint, SwiftFormat, xcodes, xcbeautify, fastlane, SF Symbols). On by default for `personal`. |

The per-profile defaults the wizard pre-checks live in the `[profileDefaults]`
table of `modules.toml`. That table **must** mirror the `$defaults` blocks in
[`.chezmoi.toml.tmpl`](../src/.chezmoi.toml.tmpl) — the config template
renders before `.chezmoidata` loads, so it can't read the table and restates
the lists literally. `tests/data-model.bats` enforces the match so the two
never drift.

## The wizard

The setup questions (`profile`, `signingMode`, and the `modules`
multi-select) are chezmoi's own `init` prompt data, defined in
[`.chezmoi.toml.tmpl`](../src/.chezmoi.toml.tmpl) with `*Once` semantics so
re-running is idempotent. But chezmoi renders those prompts as an interactive
TUI picker that is unreliable under `curl | bash` and some terminals (it can
fail to register navigation and just confirm the default). So
[`scripts/bin/wizard.sh`](../scripts/bin/wizard.sh) is the front-end: it asks
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

`bash scripts/bin/wizard.sh` (or `chezreset`) is the "change the setup" path;
`chezreset` also replays first-time setup. See
[commands.md](commands.md#changing-your-setup) for how reset/reinit differ.

## Adding a package

- **A tool everyone gets** → add it to the core [`Brewfile`](../packages/Brewfile),
  alphabetically within its section.
- **Profile- or module-specific** → add it to the matching layer file. If it's
  a new module, add the catalog entry to `modules.toml`, its Brewfile mapping
  to `packages.toml`, and mirror the default into `.chezmoi.toml.tmpl`.

CI resolves every Homebrew name on macOS (`scripts/ci/brew-resolve.sh`) and
checks module wiring (`brew-check-modules.sh`), so a typo'd formula or
unmapped module fails the build. See [development.md](development.md).
