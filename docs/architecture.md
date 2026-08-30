# Architecture & repository layout

The repo root splits into **what chezmoi deploys** and **the tooling that
supports it**. Understand that split and everything else falls out of it.

## The `src/` split

[`.chezmoiroot`](../.chezmoiroot) (one line, `src`) makes `src/` chezmoi's
**source directory**: everything under it renders into `$HOME`, and everything
at the repo **root** (`core/`, `scripts/`, `packages/`, `tests/`, `docs/`,
`install.sh`, `.github/`) is tooling chezmoi never sees.

Two rules follow:

1. **Edit source files, never the rendered copies in `$HOME`.** `chezmoi apply`
   overwrites local drift — every entry point (`install.sh`, the wizard,
   `chezup`/`chezapply`) passes `--force`, since chezmoi has no config key for
   it and would otherwise prompt per changed file. Edit via
   `chezmoi edit ~/.X`, or capture a live edit back into source with
   `chezmoi re-add ~/.X`.
2. **Inside a hook, `{{ .chezmoi.sourceDir }}` is `…/dotfiles/src`.** So
   reaching root-level tooling (`core/*`, the `scripts/lib/*` engines,
   `features/brew/Brewfile*`) uses `{{ .chezmoi.workingTree }}` — the git working
   tree, i.e. the repo root. That's the one path idiom the hooks rely on.

## chezmoi naming conventions

The special prefixes/suffixes change how a file is deployed — preserve them:

| Marker | Effect |
|---|---|
| `dot_*` | Renders to a `.`-prefixed name (`dot_zshenv` → `~/.zshenv`). |
| `private_dot_*` | Same, but `0600` perms (`private_dot_ssh/` → `~/.ssh/`). |
| `executable_*` | Renders with `+x` set (`executable_statusline.sh`). |
| `symlink_*` | Renders as a symlink whose target is the file's contents (`symlink_personal.txt.tmpl`). |
| `remove_*` | Removes the target path from `$HOME` (used to retire old files). |
| `run_*` | A hook script — see [lifecycle.md](lifecycle.md). |
| `.tmpl` | A Go template, rendered with the chezmoi data model. |

## Layout

```text
.chezmoiroot            # one line: "src" — points chezmoi at the src/ subdir
src/                    # ← chezmoi's source dir; everything here deploys to $HOME
  .chezmoi.toml.tmpl    #   chezmoi config + the init-prompt setup questions
  .chezmoidata/         #   static data: module catalog + profile→Brewfile map
  .chezmoiscripts/      #   ordered run scripts (brew bundle, mise, vscode, macOS defaults…)
  dot_config/           #   → ~/.config; untracked entries reconciled on demand by chezclean (keep-list in clean.toml)
  dot_zshenv, …         #   other managed dotfiles (private_dot_ssh/, Library/, …)
packages/               # what to install: core Brewfile + profile/module layers + editor lists
core/                   # shared helpers + the registry (see below)
features/               # one directory per feature; _template/ is the skeleton
scripts/                # tooling not yet moved into a feature
install.sh              # tiny bootstrap; hands off to `chezmoi init --apply`
tests/                  # bats suites
docs/                   # these guides
```
## How the tooling is organized

Three roots, split by ownership rather than by kind:

- **[`features/`](../features)** — one directory per feature, holding its code,
  its tests and its documentation. The contract is in
  [features/README.md](../features/README.md).
- **[`core/`](../core)** — helpers that no single feature owns, so giving them
  to one would be arbitrary, plus the registry. Sourced, never run directly.
- **[`scripts/`](../scripts)** — what has not moved into a feature yet, grouped
  by *who invokes it*:
  - **[`scripts/bin/`](../scripts/bin)** — user-facing verbs run by hand or via
    the zsh functions: `chezup`, `doctor`, `bootstrap-auth`, `wizard`,
    `macos-defaults`, `clean`, `signing`, `xcode`, `distill`. Documented in
    [commands.md](commands.md).
  - **[`scripts/ci/`](../scripts/ci)** — checks wired into CI and the
    pre-commit hooks: `lint-config`, `render-check`, `brew-resolve`,
    `brew-check-modules`, `check-commit-msg`. Documented in
    [development.md](development.md).
  - **[`scripts/lib/`](../scripts/lib)** — the remaining engines, each owned by
    exactly one feature: `brewfiles.sh`, `homebrew.sh`, `brew-progress.sh`,
    `vscode.sh`, `xcode.sh`, `xcodes.sh`, `git-signing.sh`, `distill.sh`.

The rule for which root a file belongs in is one sentence: *if exactly one
feature cares about it, it belongs to that feature.* `scripts/` shrinks to
nothing as the features are moved across, one PR each; every file still in it
has a named destination in its feature's README.

### The registry

Two files describe the whole surface, and everything else reads them, which is
what stops the descriptions drifting apart again.

| File | Declares |
|---|---|
| [`core/verbs.sh`](../core/verbs.sh) | Every verb: its owning feature, the script it runs, its group in `chez help`, its module gate, its one-line summary. The single source of truth for the command surface. |
| `features/<name>/feature.sh` | What a feature *is*: name, title, the module that gates it, where its checks belong in `chezdoctor`'s order. Data only — sourced in a subshell, no side effects. |

[`core/chez.sh`](../core/chez.sh) is the only consumer that matters day to day.
It reads the table three ways from the one row: to resolve `chez <verb>` to a
script, to render `chez help`, and to answer `chez --verbs` for the zsh
completion. A verb added to the table therefore dispatches, documents itself and
completes without a second edit anywhere.

`chez` is a zsh *function*, not a script, for one reason: `chez cd` changes the
calling shell's directory. Everything else it hands to `core/chez.sh` through
`_chez_run`, which self-heals a shell config that predates a repo change. Module
gating is passed in as `CHEZ_MODULES` at render time rather than read back from
`chezmoi data`, so neither help nor dispatch pays a ~200 ms subprocess.

Verbs are declared in exactly one of those files, never both. The list used to
live in five hand-written places — the `chezhelp` heredoc, `README.md`,
`docs/commands.md`, the `99-completion` hook and `CLAUDE.md` — with only one of
them checked, in one direction. Three of the five are generated now.
`tests/registry.bats` holds the prose that is left to the table in *both*
directions, and checks that every module gate names a real module, that doctor
orders are unique, and that every `.chezmoidata` file has an owner.

Ordering in `chez doctor` comes from `FEATURE_DOCTOR_ORDER`, never from the
directory name: the current section order is deliberate — repo, chezmoi,
identity, packages, runtimes, optional modules, informational — and
alphabetical would scramble it.

The report is the registry's second consumer. `features/doctor/cli.sh` owns only
the tallies, the order and the summary; each section is a **sourced fragment**
at `features/<name>/doctor.sh` defining one `doctor_<name>()`. Sourced rather
than executed so the fragments share one set of counters — running them as
subprocesses would mean rebuilding the same four numbers out of fifteen exit
codes. The checks belonging to no feature live in `features/doctor/checks/`,
carrying their order in the filename on the same numeric scale. Full model in
[features/doctor](../features/doctor/README.md).

`bin/` and `ci/` scripts reach `core/` as `"$_DIR/../../core/…"` and their own
engines as `"$_DIR/../lib/…"`; the chezmoi hooks reach both across the
source/root boundary via `{{ .chezmoi.workingTree }}/…`.

### Shared helpers (core/)

| Helper | Provides | Sourced by |
|---|---|---|
| `ui.sh` | colors, glyphs, rail + flat status helpers, `explain` / `explain_titled` | chezup, bootstrap-auth, wizard, doctor, macos-defaults, clean, distill, signing, xcode, `run_after_02` |
| `chezmoi-data.sh` | `cm_data_json/string/bool`, `cm_has_module` | doctor, wizard, bootstrap-auth, signing, distill |
| `tty.sh` | `tty_reattach` (stdin → controlling terminal) | `run_before_00`, `run_after_02`, `run_onchange_after_04` |
| `sudo.sh` | `sudo_keep_warm` (background sudo-timestamp refresh; survives isolated failed refreshes, gives up after `SUDO_KEEP_WARM_MAX_MISSES`) | `run_before_00`, `run_after_02` (pre-flight before the bundle), macos-defaults, xcode |
| `dry-run.sh` | `run` (DRY_RUN command wrapper) | chezup, clean, distill, xcode |
| `semver.sh` | `semver_extract` / `semver_lt` | doctor |
| `prompt-meta.sh` | `prompt_msg` / `prompt_choices` — reads prompt text back out of `.chezmoi.toml.tmpl`, so no caller hardcodes it | wizard, signing |
| `modules.sh` | this Mac's module selection: `modules_unseen` (catalog − enabled − seen), `modules_label`, `modules_write_list` (rewrite one `key = [...]` line in the generated chezmoi config) | chezup (new-module gate), distill (`--setup`) |

The everyday scripts share the tiny terminal UI library `core/ui.sh`:

- `ui_init_colors` / `ui_init_glyphs` — palette + Unicode/ASCII glyphs.
- `ui_init_logging` — the rail-style log helpers (`say`/`ok`/`info`/`warn`/
  `fail`/`dim`/`hr` plus `line_prefix`/`node_prefix`); inits colors + glyphs
  first.
- `ui_init_status` — the flat status helpers (`s_pass`/`s_warn`/`s_note`/
  `s_fail`/`s_info`/`s_section`) for the report-style scripts (`doctor`);
  inits colors + glyphs first.
- `explain` / `explain_titled` — the plain-language preamble every verb prints
  before acting. `explain_titled` is the one with a heading, and is kept
  byte-identical to the zsh-native `_chez_explain` still in `dot_zshrc.tmpl`
  (pinned by `tests/ui.bats`) so verbs can move out of that template without
  changing what they print.

`scripts/ci/check-commit-msg.sh` (the Conventional-Commit subject validator
run by the commit-msg pre-commit hook) is an executed check, not a sourced
lib, so it lives under `ci/`.
