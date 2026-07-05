# Packages, profiles & modules

What gets installed is chosen by two answers you give the [wizard](#the-wizard):
your **profile** and your **optional modules**. Both feed a single data model in
[`src/.chezmoidata/`](../src/.chezmoidata) that the apply hooks and the doctor
report all read, so the mapping is never restated in more than one place.

## Package tiers

Packages are layered Brewfiles under [`packages/`](../packages). The active set
is the core file plus whatever your profile and modules add:

| Tier | File | Installed when |
|---|---|---|
| **Core** | [`Brewfile`](../packages/Brewfile) | Always. The smallest set that makes the documented shell experience work. |
| **Profile** | `Brewfile.personal` / `Brewfile.work` | Your profile matches. `work` adds the cloud/Kubernetes/IaC CLIs (az, gcloud, kubectl, kubectx, kubelogin, terraform, helm, minikube) and work apps (M365, Teams, Slack). |
| **Module** | `Brewfile.mac-apps` | The matching module is selected (`macApps` → GUI + AI apps). |

The profile→file and module→file mappings live in
[`src/.chezmoidata/packages.toml`](../src/.chezmoidata/packages.toml) — the
single source of truth. The `run_after_02-brew-bundle` hook reads the active set
from there and runs `brew bundle --no-upgrade`, so it converges *presence*, not
freshness. See [lifecycle.md](lifecycle.md#where-each-piece-lives).

## Profiles

One of `personal`, `work`, or `minimal`, chosen at setup. A profile selects its
Brewfile layer and pre-checks a default set of modules (below).

## Optional modules

A multi-select of add-ons, catalogued in
[`src/.chezmoidata/modules.toml`](../src/.chezmoidata/modules.toml). Templates
gate on membership with sprig `has`, e.g. `{{ if has "theme" .modules }}…{{ end }}`.

| Module | What it adds |
|---|---|
| `macApps` | GUI and AI apps (Raycast, Obsidian, Chrome, Claude, Ollama). |
| `macosDefaults` | macOS system defaults (needs sudo). |
| `cloudAuth` | Cloud CLIs and auth walkthrough (gh, az, gcloud, op). |
| `obsidian` | Obsidian vault seeding and starter content. |
| `claudePersona` | Claude persona at `~/.config/claude/CLAUDE.md` (see [ai.md](ai.md)). |
| `theme` | Catppuccin Frappé across terminal and editor (see [terminal.md](terminal.md)). |
| `locale` | Norwegian locale (cSpell `nb`, bokmål dictionary). |
| `jvmStack` | JVM runtimes via mise (Temurin, Kotlin, Maven, Gradle — see [shell.md](shell.md#runtimes-mise)). |

The per-profile default selections the wizard pre-checks are in the
`[profileDefaults]` table of `modules.toml`. That table **must** mirror the
`$defaults` blocks in [`.chezmoi.toml.tmpl`](../src/.chezmoi.toml.tmpl) — the
config template renders before `.chezmoidata` loads, so it can't read the table
and has to restate the lists literally. `tests/data-model.bats` enforces the
match so the two never drift.

## The wizard

The setup questions (`profile`, `signingMode`, and the `modules` multi-select)
are chezmoi's own `init` prompt data, defined in
[`.chezmoi.toml.tmpl`](../src/.chezmoi.toml.tmpl) with `*Once` semantics so
re-running is idempotent. But chezmoi renders those prompts as an interactive TUI
picker that is unreliable under `curl | bash` and some terminals (it can fail to
register navigation and just confirm the default). So
[`scripts/bin/wizard.sh`](../scripts/bin/wizard.sh) is the front-end: it asks each
question with plain `read` from `/dev/tty` and passes the answers to
`chezmoi init --apply` via its `--promptString/-Choice/-Multichoice` flags — no
TUI.

The prompts have three tiers, degrading to fit the terminal:

- **gum** pickers when `gum` is installed (any re-run after the first install),
  with your current selection pre-checked;
- a **pure-bash arrow/space picker** when there's no gum yet but the terminal is
  capable (the first-boot case — it also accepts number keys, so it works even if
  arrows don't register); and
- the **numbered menu** on a dumb/non-ANSI terminal.

`WIZARD_NO_GUM=1` skips the first tier, `WIZARD_NO_TUI=1` the first two.

`bash scripts/bin/wizard.sh` (or `chezreset`) is the "change my setup" path;
`chezreset` also replays first-time setup. See
[commands.md](commands.md#changing-your-setup) for how the reset/reinit verbs
differ.

## Adding a package

- **A tool everyone gets** → add it to the core [`Brewfile`](../packages/Brewfile),
  alphabetically within its section.
- **Profile- or module-specific** → add it to the matching layer file. If it's a
  new module, add the catalog entry to `modules.toml`, its Brewfile mapping to
  `packages.toml`, and mirror the default into `.chezmoi.toml.tmpl`.

CI resolves every Homebrew name on macOS (`scripts/ci/brew-resolve.sh`) and
checks module wiring (`brew-check-modules.sh`), so a typo'd formula or an
unmapped module fails the build. See [development.md](development.md).
