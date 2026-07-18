# Editors

Two editors are managed: **VS Code** for GUI work and **Neovim** (LazyVim) in the
terminal, both themed Catppuccin Frappé. IntelliJ is installed for non-trivial
Java/Kotlin (via the `macApps` module) but isn't config-managed here.

## VS Code

The app comes from the core Brewfile (`visual-studio-code`); its settings and
extensions are managed by chezmoi.

- **Settings** —
  [`src/Library/Application Support/Code/User/settings.json.tmpl`](../src/Library/Application%20Support/Code/User/settings.json.tmpl)
  and `keybindings.json` alongside it. The settings are a template so they can
  anchor to stable paths — e.g. `java.configuration.runtimes` points at mise's
  non-churning JDK install paths
  (`~/.local/share/mise/installs/java/temurin-*/Contents/Home`), so the Java
  language server never breaks on a runtime bump. See
  [shell.md](shell.md#runtimes-mise).
- **Extensions** — the single source of truth is
  [`packages/vscode-extensions.txt`](../packages/vscode-extensions.txt). The
  `run_onchange_after_03-vscode` hook **mirrors** it onto the machine: installs
  every ID the manifest lists, uninstalls any extension not in it (re-fires only
  when the list changes — see [lifecycle.md](lifecycle.md)). `chezdoctor` reports
  drift in both directions read-only; the set logic lives in
  [`scripts/lib/vscode.sh`](../scripts/lib/vscode.sh) (unit-tested by
  `tests/vscode.bats`). The set covers the language toolchain: the Java/Spring
  pack, Kotlin, Gradle/Maven, plus Terraform, Kubernetes, Helm, Docker, Postgres,
  Python/Ruff, and shell/YAML/TOML tooling. Several extensions are backed by CLIs
  from the Brewfile (hadolint, shellcheck, shfmt, helm, minikube) so they use the
  pinned binary instead of downloading their own. A few entries are **module-gated**
  in the hook — excluded from install *and* prune when the module is off: the
  Norwegian dictionary (`locale`), and the Swift/iOS extensions (`appleDev`, below).

### Swift / iOS in VS Code (`appleDev`)

The goal is to keep VS Code as the daily driver and drop into Xcode only when
something genuinely needs it (Interface Builder, asset catalogs, signing UI). Three
gated extensions plus one Homebrew tool make that work:

- **`swiftlang.swift-vscode`** — the official Swift extension; drives SourceKit-LSP
  for completion, diagnostics, and jump-to-def. SourceKit-LSP itself ships inside
  Xcode and follows `xcode-select`, so keep an Xcode selected via `xcodes`.
- **`sweetpad.sweetpad`** — the Xcode-replacement half: build/run/debug on the
  Simulator, a destination picker, and `xcbeautify`'d output. It shells out to
  `xcodebuild` and formats through Homebrew **swiftformat** (`[swift]` formatter).
- **`vadimcn.vscode-lldb`** (CodeLLDB) — the debugger Sweetpad drives for
  breakpoints and stepping.
- **`xcode-build-server`** (Brewfile) — the missing bridge for
  `.xcodeproj`/`.xcworkspace` projects: it writes `buildServer.json` so
  SourceKit-LSP knows how each file compiles. Plain SwiftPM packages don't need it;
  app projects do. Run Sweetpad's *“Generate Build Server Config”* once per project.

Shell shortcuts (`xcb`, `xcderived`, `simulator`) come with the same module — see
[shell.md](shell.md). None of this touches the `work`/`minimal` profiles.

## Neovim

LazyVim, bootstrapped from
[`src/dot_config/nvim/init.lua`](../src/dot_config/nvim/init.lua) →
`lua/config/lazy.lua`, with `lazy-lock.json` committed for reproducible plugin
versions. The only preset override is the colorscheme
([`lua/plugins/colorscheme.lua`](../src/dot_config/nvim/lua/plugins/colorscheme.lua)):
Catppuccin Frappé replacing LazyVim's default tokyonight, with integrations for
cmp, gitsigns, treesitter, telescope, and LSP (undercurl diagnostics).

`n` → `nvim` and it's git's `core.editor`. See [terminal.md](terminal.md) for the
shared theme and font.
