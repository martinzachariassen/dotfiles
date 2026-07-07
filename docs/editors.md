# Editors

Two editors are managed: **VS Code** for GUI work and **Neovim** (LazyVim) in the
terminal. Both are themed Catppuccin Frappé to match the terminal. IntelliJ is
installed for non-trivial Java/Kotlin (via the `macApps` module) but isn't
config-managed here.

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
- **Extensions** — listed in
  [`packages/vscode-extensions.txt`](../packages/vscode-extensions.txt), which is
  the single source of truth. The `run_onchange_after_03-vscode` hook **mirrors**
  it onto the machine: it installs every ID the manifest lists and uninstalls any
  extension not in it (re-fires only when the list changes — see
  [lifecycle.md](lifecycle.md)). `chezdoctor` reports drift in both directions
  read-only, and the set logic lives in
  [`scripts/lib/vscode.sh`](../scripts/lib/vscode.sh) (unit-tested by
  `tests/vscode.bats`). The set covers the backend
  stack: the Java/Spring pack, Kotlin, Gradle/Maven, plus Terraform, Kubernetes,
  Helm, Docker, Postgres, Python/Ruff, and the shell/YAML/TOML tooling. Several
  extensions are backed by CLIs from the Brewfile (hadolint, shellcheck, shfmt,
  helm, minikube) so they use the pinned binary instead of downloading their own.

## Neovim

LazyVim, bootstrapped from
[`src/dot_config/nvim/init.lua`](../src/dot_config/nvim/init.lua) →
`lua/config/lazy.lua`, with `lazy-lock.json` committed for reproducible plugin
versions. The only preset override is the colorscheme
([`lua/plugins/colorscheme.lua`](../src/dot_config/nvim/lua/plugins/colorscheme.lua)):
Catppuccin Frappé replacing LazyVim's default tokyonight, with integrations for
cmp, gitsigns, treesitter, telescope, LSP (undercurl diagnostics), and more.

`n` → `nvim` and it's git's `core.editor`. See [terminal.md](terminal.md) for the
shared theme and font.
