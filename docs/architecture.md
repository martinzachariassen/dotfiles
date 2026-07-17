# Architecture & repository layout

The repo root splits cleanly into **what chezmoi deploys** and **the tooling that
supports it**. Understand that split and everything else falls out of it.

## The `src/` split

[`.chezmoiroot`](../.chezmoiroot) (one line, `src`) makes `src/` chezmoi's
**source directory**: everything under it renders into `$HOME`, and everything at
the repo **root** (`scripts/`, `packages/`, `tests/`, `docs/`, `install.sh`,
`.github/`) is tooling chezmoi never sees.

Two rules follow:

1. **Edit source files, never the rendered copies in `$HOME`.** `chezmoi apply`
   overwrites local drift (`apply.force = true`). Edit via
   `chezmoi edit ~/.X`, or capture a live edit back into source with
   `chezmoi re-add ~/.X`.
2. **Inside a hook, `{{ .chezmoi.sourceDir }}` is `…/dotfiles/src`.** So reaching
   root-level tooling (the `scripts/lib/*` engines, `packages/Brewfile*`) uses
   `{{ .chezmoi.workingTree }}` — the git working tree, i.e. the repo root —
   instead. That's the one path idiom the hooks rely on.

## chezmoi naming conventions

The special prefixes/suffixes change how a file is deployed — preserve them:

| Marker | Effect |
|---|---|
| `dot_*` | Renders to a `.`-prefixed name (`dot_zshenv` → `~/.zshenv`). |
| `private_dot_*` | Same, but `0600` perms (`private_dot_ssh/` → `~/.ssh/`). |
| `remove_*` | Removes the target path from `$HOME` (used to retire old files). |
| `run_*` | A hook script — see [lifecycle.md](lifecycle.md). |
| `.tmpl` | A Go template, rendered with the chezmoi data model. |

## Layout

```
.chezmoiroot            # one line: "src" — points chezmoi at the src/ subdir
src/                    # ← chezmoi's source dir; everything here deploys to $HOME
  .chezmoi.toml.tmpl    #   chezmoi config + the init-prompt setup questions
  .chezmoidata/         #   static data: module catalog + profile→Brewfile map
  .chezmoiscripts/      #   ordered run scripts (brew bundle, mise, vscode, macOS defaults…)
  dot_config/           #   → ~/.config (zsh, git, mise, nvim, ghostty, starship, claude…)
  dot_zshenv, …         #   other managed dotfiles (private_dot_ssh/, Library/, …)
packages/               # what to install: core Brewfile + profile/module layers + editor lists
scripts/                # tooling, grouped by who runs it (see below)
install.sh              # tiny bootstrap; hands off to `chezmoi init --apply`
tests/                  # bats suites
docs/                   # these guides
```

## How `scripts/` is organized

Grouped by *who invokes each script*, so the entry points are obvious at a
glance:

- **[`scripts/bin/`](../scripts/bin)** — user-facing verbs run by hand or via the
  zsh functions: `chezup`, `doctor`, `bootstrap-auth`, `wizard`, `setup-ollama`,
  `macos-defaults`. Documented in [commands.md](commands.md).
- **[`scripts/ci/`](../scripts/ci)** — checks wired into CI and the pre-commit
  hooks: `lint-config`, `render-check`, `brew-resolve`, `brew-check-modules`,
  `check-commit-msg`. Documented in [development.md](development.md).
- **[`scripts/lib/`](../scripts/lib)** — helpers the above `source`, never run
  directly.

`bin/` and `ci/` scripts reach the helpers one level up as `"$_DIR/../lib/…"`;
the chezmoi hooks reach them across the source/root boundary via
`{{ .chezmoi.workingTree }}/scripts/lib/…`.

### Shared libraries (`scripts/lib/`)

| Lib | Provides | Sourced by |
|---|---|---|
| `log.sh` | colors, glyphs, rail + flat status helpers | chezup, bootstrap-auth, setup-ollama, wizard, doctor, macos-defaults |
| `chezmoi-data.sh` | `cm_data_json/string/bool`, `cm_toml_*` readers | doctor, wizard |
| `tty.sh` | `tty_reattach` (stdin → controlling terminal) | `run_before_00`, `run_after_02`, `run_onchange_after_04` |
| `semver.sh` | `semver_extract` / `semver_lt` | doctor |

The everyday scripts share the tiny logging library `log.sh`:

- `ui_init_colors` / `ui_init_glyphs` — palette + Unicode/ASCII glyphs.
- `ui_init_logging` — the rail-style log helpers (`say`/`ok`/`info`/`warn`/
  `fail`/`dim`/`hr` plus `line_prefix`/`node_prefix`); inits colors + glyphs first.
- `ui_init_status` — the flat status helpers (`s_pass`/`s_warn`/`s_note`/
  `s_fail`/`s_info`/`s_section`) for the report-style scripts (`doctor`,
  `setup-ollama`); inits colors + glyphs first.

`scripts/ci/check-commit-msg.sh` (the Conventional-Commit subject validator run
by the commit-msg pre-commit hook) is an executed check, not a sourced lib, so it
lives under `ci/`.
