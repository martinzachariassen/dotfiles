# Editors

Two editors are managed: **VS Code** for GUI work and **Neovim** (LazyVim) in
the terminal, both themed Catppuccin Mocha. IntelliJ is installed for
non-trivial Java/Kotlin (via the `work` profile) but isn't config-managed
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
  [`features/vscode/extensions.txt`](../features/vscode/extensions.txt), which
  the `run_onchange_after_03-vscode` hook **mirrors** onto the machine: it
  installs every ID listed and uninstalls anything not in it. A few entries are
  module-gated. The set covers the language toolchain — the Java/Spring pack,
  Kotlin, Gradle/Maven — plus Docker, Postgres and shell/YAML/TOML tooling. The
  IaC/Kubernetes and Python extensions were dropped 2026-08 as unused; their
  CLIs stay in the Brewfile, only the editor integrations went. How the mirror
  works, and why it prunes: [features/vscode](../features/vscode/README.md).

#### Appearance

Four choices in the settings template that aren't self-evident:

- **Catppuccin Mocha** (`catppuccin.catppuccin-vsc`, `theme`-gated) — a
  published palette with defined lightness relationships rather than
  hand-picked hex, and it has ports for every other tool here, which is what
  makes one flavour switch land everywhere ([terminal.md](terminal.md#theme)).
  Comments are overridden to subtext0 (`#a6adc8`) via
  `editor.tokenColorCustomizations`: the stock comment colour is too low in
  contrast to skim past in KDoc/Javadoc-heavy files.
- **Semantic highlighting on** — without it every token is coloured by
  TextMate regex, which can't distinguish a field from a parameter from a
  local. The language server can, and in Java/Kotlin that distinction carries
  real information.
- **Fonts** — `JetBrains Mono` (unpatched) in the editor at 14px/weight 500:
  a high x-height reads well at small sizes, and 500 compensates for macOS
  grayscale antialiasing thinning Regular on a dark background. The Nerd Font
  patch is confined to the integrated terminal, where the glyphs are actually
  used and its wider metrics don't disturb editor column alignment. Letter
  spacing is left at VS Code's default of 0 — which is IntelliJ's default too;
  adding tracking would give up the rendering parity the font choice buys.
- **Ligatures off** — `!=` and `->` should stay distinguishable at review
  speed. Ghostty keeps `calt`/`liga` on; prose and shell output don't have
  the same failure mode.

#### Vim

`vscodevim.vim` with `<space>` as leader. The organising rule is that **the
leader maps mirror LazyVim's defaults key-for-key** — this repo manages both
editors, both use `<space>`, and muscle memory is the only thing that makes
two editors cheaper than one. So `<leader>ff` opens files, `<leader>/` greps,
`<leader>ca`/`<leader>cr`/`<leader>cf` are code action / rename / format,
`<leader>bd` closes the buffer, `<leader>e` is the explorer, `]d`/`[d` walk
diagnostics, and `gr`/`gI`/`gy` are references / implementation / type
definition. Where LazyVim maps something VS Code has no equivalent for,
the nearest thing takes the slot: `<leader>gg` is lazygit there and the SCM
view here.

The inverse rule matters as much: **anything VSCodeVim emulates natively is
not remapped.** `gd`, `gc`/`gC` (vim-commentary), and `ys`/`cs`/`ds`
(vim-surround) all ship with the extension, so a `<leader>` alias for them
would just be a second spelling to keep in sync.

Two places where LazyVim parity had to lose, both because an emulated plugin
claims a sequence and neither prefix is configurable:

- **`<leader><space>` (Find Files in LazyVim) is not mapped.** With
  `leader = <space>` that sequence *is* `<space><space>`, which is
  EasyMotion's entire prefix — mapping it silently kills every
  `<leader><leader>` motion. `<leader>ff` covers the same thing.
- **`vim.replaceWithRegister` is off.** It owns `gr`, and `gr` is Goto
  References. References wins; `gr`-as-replace loses.

`tests/vscode-vim.bats` pins both of those as a table of
plugin → sequences-it-claims, checked only when the plugin is enabled. It
also pins that no key sequence may be a strict prefix of another —
`<leader>e` next to a hypothetical `<leader>ee` would stall for `vim.timeout`
(1 s) on every press.

Four settings that aren't obvious:

- **`extensions.experimental.affinity`** puts VSCodeVim in its own extension
  host process (group 1). It's upstream's one documented performance lever,
  and it matters here specifically because the shared (group 0) host also
  runs Error Lens, ESLint, and Copilot — keystroke handling otherwise queues
  behind them. The Java/Kotlin/Spring toolchain (`redhat.java`, the
  `vscjava.*` pack, `vmware.vscode-spring-boot`, `jetbrains.kotlin-server`)
  gets a second group (2), isolating the heaviest extensions in
  this setup from both the vim host and the shared default host. The cost of
  each group is the same: the extensions in it reload whenever
  `settings.json` is written, which `chezmoi apply` does often. Extensions
  that already run their language server as a separate OS process outside
  the extension host — ESLint, for one — don't benefit from affinity and are
  deliberately left out of group 2.
- **Relative line numbers** are two settings, not one:
  `editor.lineNumbers: relative` does the rendering and
  `vim.smartRelativeLine` flips back to absolute in insert mode. Either alone
  is wrong, so a bats test asserts both.
- **`vim.useSystemClipboard: true`** is a deliberate trade: every `d`/`c`/`x`
  also overwrites the macOS clipboard, in exchange for never typing `"+y`.
  Named registers (`"ayiw`) still bypass it when something has to survive a
  delete.
- **The EasyMotion palette is `theme`-gated.** EasyMotion's stock markers are
  hard-coded red/orange that clash with Catppuccin, so the marker, dim, and
  incsearch colours are overridden to Mocha — inside the same
  `{{ if has "theme" … }}` guard as the colour theme itself, and nowhere else.

`keybindings.json` stays reserved for editor chrome that vim has no concept of
(moving editors between groups, the Sweetpad build loop); every vim-side
binding lives in `settings.json` so there's one place to look.

### Swift / iOS in VS Code (appleDev)

The goal is to keep VS Code as the daily driver — for iOS, macOS, watchOS,
tvOS, and visionOS targets alike — and drop into Xcode only when something
genuinely needs it (Interface Builder, asset catalogs, signing UI). Four
gated extensions plus a handful of Homebrew tools make that work:

**Xcode.app is still a hard prerequisite for all of it**, even though you rarely
open it: SourceKit-LSP, the SDKs, `xcodebuild` and Simulator.app all live inside
it, so without one nothing below functions. It doesn't arrive with an apply —
run [`chezxcode`](commands.md#advanced--occasional-helpers) once, which installs
it, selects it, accepts the licence and downloads a simulator runtime.

- **`swiftlang.swift-vscode`** — the official Swift extension; drives
  SourceKit-LSP for completion, diagnostics, and jump-to-def.
  SourceKit-LSP itself ships inside Xcode and follows `xcode-select`, so
  keep an Xcode selected — `chezxcode` does it, and `chezdoctor` fails loudly
  when the Command Line Tools have taken the slot back. It declares
  **`llvm-vs-code-extensions.lldb-dap`** as a hard `extensionDependency`
  (VS Code auto-installs it) — tracked explicitly in the manifest so the
  extension-sync hook doesn't fight that install by trying to prune it as
  untracked.
- **`sweetpad.sweetpad`** — the Xcode-replacement half: build/run/debug/test
  across every Apple platform via its **Destinations** view (simulators,
  paired physical devices, and the local Mac itself for macOS targets),
  `xcbeautify`'d output, and a native VS Code Testing-panel integration for
  XCTest/Swift Testing. It also **owns `[swift]` formatting** now
  (`editor.defaultFormatter: sweetpad.sweetpad`) — SweetPad implements the
  real formatter-provider API (invoke → re-read → hand VS Code a text edit),
  so format-on-save no longer races the save the way a bare disk-writing CLI
  invocation would. It defaults to Xcode's bundled `swift-format`;
  `sweetpad.format.path`/`sweetpad.format.args` repoint it at Homebrew
  **swiftformat** (nicklockwood) instead, so `~/.swiftformat` keeps applying.
  It declares **`vadimcn.vscode-lldb`** (CodeLLDB) as a hard
  `extensionDependency` for its own debug/run flow — also tracked
  explicitly for the same prune-fight reason as lldb-dap above.
- **`xcode-build-server`** (Brewfile) — the bridge for
  `.xcodeproj`/`.xcworkspace` projects: it writes `buildServer.json` so
  SourceKit-LSP knows how each file compiles. Plain SwiftPM packages don't
  need it; app projects do. Run SweetPad's *"Generate Build Server Config"*
  once per project. (SweetPad also ships an experimental built-in build
  server needing no prior build — `sweetpad.buildServer.provider: sweetpad`
  — but it's currently limited to plain `.xcodeproj`, not `.xcworkspace`
  with SPM/CocoaPods dependencies, so `xcode-build-server` stays the
  default here.)
- **`xcodegen`** (Brewfile) — generates `.xcodeproj` from a plain-YAML
  `project.yml`, so the project file is never hand-edited (or
  merge-conflicted) in Xcode's project navigator. Run
  *"SweetPad: Generate an Xcode project using XcodeGen"* once a `project.yml`
  exists at the workspace root; `sweetpad.xcodegen.autogenerate: true` (set
  globally, a no-op without a `project.yml`) then re-runs it automatically
  whenever a Swift file is added or removed, restart VS Code once to pick it
  up. This is the biggest lever for staying out of Xcode day-to-day: adding a
  new file is a text edit, not a trip to the project navigator.

**No hover docs and no ⌘-click on any SDK symbol?** A missing
`buildServer.json` is the cause, and it fails *silently* and *totally*: with
no compile arguments, SourceKit-LSP can't resolve a single module, so even
`EmptyView` goes dead alongside anything exotic. That everything fails —
not just the obscure symbols — is the tell; it's never a missing
documentation tool. Check for `buildServer.json` at the workspace root,
then build once and run *"SweetPad: Generate Build Server Config"* (it
restarts the LSP too; from a shell it's `xcode-build-server config -scheme
NAME -project NAME.xcodeproj` plus *"Swift: Restart LSP Server"*).
It goes missing in the first place because
`sweetpad.build.autoGenerateBuildServerConfig` (default `true`) only
regenerates on **SweetPad's own** builds — building from Xcode or plain
`xcodebuild` doesn't — and the file holds machine-local absolute paths, so
it's gitignored per project and never survives a fresh clone.

The docs themselves are always already on disk: Apple ships a `.swiftdoc`
next to each `.swiftinterface` in the SDK
(`…/SwiftUI.framework/Modules/SwiftUI.swiftmodule/`), and that — not the
`.swiftinterface`, which carries no `///` comments — is where the prose
SourceKit-LSP shows on hover comes from. So there's nothing to install for
documentation; `bierner.docs-view` (hover docs pinned in a sidebar panel)
was considered as a nicety and rejected on the usual bar — untouched
upstream since January 2024.

**No SwiftLint editor integration.** `vknabel.vscode-swiftformat` and
`vknabel.vscode-swiftlint` — previously wired up here — were archived
upstream (unmaintained) on 2025-11-19 and removed 2026-08; there is
currently no actively-maintained VS Code extension surfacing SwiftLint as
you type (the only other option, `shinnn/vscode-swiftlint`, hasn't been
touched since 2018). This is a real gap, not a downgrade dressed up as one:
the underlying **swiftlint** and **swiftformat** CLIs are both still
actively developed — only the thin VS Code wrapper extensions died.
SwiftFormat is unaffected (SweetPad drives it directly, above). SwiftLint
now runs two ways instead:

1. An Xcode **Run Script build phase** (one-time, per-project, added in
   Xcode itself) — `xcodebuild` runs it regardless of whether you build from
   Xcode or SweetPad's CLI wrapper, so warnings surface through SweetPad's
   build-log diagnostics on every build:
   ```sh
   if [ -f "${SRCROOT}/.swiftlint.yml" ]; then
     swiftlint lint
   else
     swiftlint lint --config "$HOME/.config/swiftlint/config.yml"
   fi
   ```
2. Directly via CLI or the pre-commit hook — `swiftlint --config
   ~/.config/swiftlint/config.yml` — same as before, just no live squiggles
   while typing.

The two committed config files still supply the *rules*, deployed to
`$HOME` and gated on `appleDev`:

- [`src/dot_swiftformat`](../src/dot_swiftformat) → `~/.swiftformat`.
  SwiftFormat ascends the directory tree from each file, so this applies to
  every Swift project under `$HOME` without a closer `.swiftformat`, and a
  project's own file overrides it. The key line is `--maxwidth 120`:
  SwiftFormat's default is *no* wrapping, so long lines were never
  reformatted even though SwiftLint flagged them.
- [`src/dot_config/swiftlint/config.yml`](../src/dot_config/swiftlint/config.yml)
  → `~/.config/swiftlint/config.yml`. SwiftLint *doesn't* ascend to
  `$HOME` — pass `--config` explicitly (Run Script phase or CLI, above); a
  project's own `.swiftlint.yml` still wins when present. `line_length` is
  pinned to 120 to match SwiftFormat, so the linter and formatter agree on
  where a line is too long instead of one flagging what the other won't fix.

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
Catppuccin Mocha replacing LazyVim's default tokyonight, with integrations
for cmp, gitsigns, treesitter, telescope, and LSP (undercurl diagnostics).

`n` → `nvim` and it's git's `core.editor`. See [terminal.md](terminal.md) for
the shared theme and font.
