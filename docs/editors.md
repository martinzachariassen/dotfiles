# Editors

Two editors are managed: **VS Code** for GUI work and **Neovim** (LazyVim) in
the terminal, both themed Catppuccin Frappé. IntelliJ is installed for
non-trivial Java/Kotlin (via the `macApps` module) but isn't config-managed
here.

## VS Code

The app comes from the core Brewfile (`visual-studio-code`); its settings and
extensions are managed by chezmoi.

- **Settings** —
  [`src/Library/Application Support/Code/User/settings.json.tmpl`](../src/Library/Application%20Support/Code/User/settings.json.tmpl)
  and `keybindings.json` alongside it. The settings are a template so they
  can anchor to stable paths — e.g. `java.configuration.runtimes` points at
  mise's non-churning JDK install paths
  (`~/.local/share/mise/installs/java/temurin-*/Contents/Home`), so the Java
  language server never breaks on a runtime bump. See
  [shell.md](shell.md#runtimes-mise).
- **Extensions** — the single source of truth is
  [`packages/vscode-extensions.txt`](../packages/vscode-extensions.txt). The
  `run_onchange_after_03-vscode` hook **mirrors** it onto the machine:
  installs every ID the manifest lists, uninstalls any extension not in it
  (re-fires only when the list changes — see [lifecycle.md](lifecycle.md)).
  `chezdoctor` reports drift in both directions read-only; the set logic
  lives in [`scripts/lib/vscode.sh`](../scripts/lib/vscode.sh) (unit-tested
  by `tests/vscode.bats`). The set covers the language toolchain: the
  Java/Spring pack, Kotlin, Gradle/Maven, plus Terraform, Kubernetes, Helm,
  Docker, Postgres, Python/Ruff, and shell/YAML/TOML tooling. Several
  extensions are backed by CLIs from the Brewfile (hadolint, shellcheck,
  shfmt, helm, minikube) so they use the pinned binary instead of
  downloading their own. A few entries are **module-gated** in the hook —
  excluded from install *and* prune when the module is off: the Norwegian
  dictionary (`locale`), and the Swift/iOS extensions (`appleDev`, below).

### Swift / iOS in VS Code (appleDev)

The goal is to keep VS Code as the daily driver and drop into Xcode only
when something genuinely needs it (Interface Builder, asset catalogs,
signing UI). Five gated extensions plus two Homebrew tools make that work:

- **`swiftlang.swift-vscode`** — the official Swift extension; drives
  SourceKit-LSP for completion, diagnostics, and jump-to-def.
  SourceKit-LSP itself ships inside Xcode and follows `xcode-select`, so
  keep an Xcode selected via `xcodes`.
- **`sweetpad.sweetpad`** — the Xcode-replacement half: build/run/debug on
  the Simulator, a destination picker, and `xcbeautify`'d output. It shells
  out to `xcodebuild`. It is *not* wired up as the `[swift]` formatter:
  Sweetpad formats by invoking `swiftformat` in place on disk, which races
  VS Code's save and produces the "content of the file is newer" conflict
  (worse under `files.autoSave: afterDelay`). Formatting is delegated to the
  SwiftFormat extension instead (below); Sweetpad keeps build/run/debug
  only.
- **`vknabel.vscode-swiftformat`** — the `[swift]` formatter. Runs the
  *same* Homebrew **swiftformat** binary (`swiftformat.path`) and the
  *same* `~/.swiftformat` config, but pipes the buffer through stdin and
  returns text edits for VS Code to apply to the in-memory document — no
  on-disk write, so format-on-save never races the save. This is the fix
  for the save-conflict prompt the disk-editing formatters caused.
- **`vadimcn.vscode-lldb`** (CodeLLDB) — the debugger Sweetpad drives for
  breakpoints and stepping.
- **`vknabel.vscode-swiftlint`** — surfaces Homebrew **swiftlint** as
  inline diagnostics (`swiftlint.path`), reusing the same binary a build
  phase or pre-commit hook would call. SourceKit-LSP itself doesn't lint.
  Autocorrect is **off the save cycle**: `swiftlint --fix` rewrites the file
  on disk (`source.fixAll` invokes `source.fixAll.swiftlint`, which spawns
  the CLI against the file path), the same save-conflict mechanism as the
  disk-editing formatter — so `[swift]` sets
  `editor.codeActionsOnSave: {}`. Apply fixable violations on demand with
  `cmd+ctrl+l` (bound to `swiftlint.fixDocument`) or via pre-commit;
  SwiftFormat already covers most autocorrectable style on save. Note: the
  extension is archived upstream (unmaintained) as of writing; if it ever
  breaks against a newer VS Code/Swift toolchain there's no active fork to
  fall back to yet.
- **`xcode-build-server`** (Brewfile) — the missing bridge for
  `.xcodeproj`/`.xcworkspace` projects: it writes `buildServer.json` so
  SourceKit-LSP knows how each file compiles. Plain SwiftPM packages don't
  need it; app projects do. Run Sweetpad's *"Generate Build Server Config"*
  once per project.

The extensions run the binaries; two committed config files supply the
*rules*, deployed to `$HOME` and gated on `appleDev`:

- [`src/dot_swiftformat`](../src/dot_swiftformat) → `~/.swiftformat`.
  SwiftFormat ascends the directory tree from each file, so this applies to
  every Swift project under `$HOME` without a closer `.swiftformat`, and a
  project's own file overrides it. The key line is `--maxwidth 120`:
  SwiftFormat's default is *no* wrapping, so long lines were never
  reformatted even though SwiftLint flagged them.
- [`src/dot_config/swiftlint/config.yml`](../src/dot_config/swiftlint/config.yml)
  → `~/.config/swiftlint/config.yml`. SwiftLint *doesn't* ascend to
  `$HOME`, so the VS Code extension wires it in via
  `swiftlint.configSearchPaths` — project `.swiftlint.yml` first, this file
  as the fallback. `line_length` is pinned to 120 to match SwiftFormat, so
  the linter and formatter agree on where a line is too long instead of one
  flagging what the other won't fix.

Line length is the one rule the two must agree on: SwiftLint only *warns*
about it (it can't autocorrect line length), while SwiftFormat is what
actually wraps — so both are set to 120.

Shell shortcuts (`xcb`, `xcderived`, `simulator`) come with the same module
— see [shell.md](shell.md). None of this touches the `work`/`minimal`
profiles.

## Neovim

LazyVim, bootstrapped from
[`src/dot_config/nvim/init.lua`](../src/dot_config/nvim/init.lua) →
`lua/config/lazy.lua`, with `lazy-lock.json` committed for reproducible
plugin versions. The only preset override is the colorscheme
([`lua/plugins/colorscheme.lua`](../src/dot_config/nvim/lua/plugins/colorscheme.lua)):
Catppuccin Frappé replacing LazyVim's default tokyonight, with integrations
for cmp, gitsigns, treesitter, telescope, and LSP (undercurl diagnostics).

`n` → `nvim` and it's git's `core.editor`. See [terminal.md](terminal.md) for
the shared theme and font.
