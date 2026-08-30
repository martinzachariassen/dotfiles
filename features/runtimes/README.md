# Language runtimes (mise)

mise owns every language runtime — never asdf/nvm/jenv/pyenv/SDKMAN, and not
Homebrew. Homebrew owns global CLIs and apps. It also owns the handful of tools
whose version a *project* wants to pin (`just`), which is exactly the property a
Brewfile cannot give.

| Piece | Where |
|---|---|
| Apply engine | [`hook.sh`](hook.sh), run by `run_after_02b-mise-install` |
| Global versions | [`src/dot_config/mise/config.toml.tmpl`](../../src/dot_config/mise/config.toml.tmpl) |
| Interactive activation | `mise activate` in [`src/dot_config/zsh/dot_zshrc.tmpl`](../../src/dot_config/zsh/dot_zshrc.tmpl) |
| Shims for GUI apps | [`src/dot_config/zsh/dot_zprofile`](../../src/dot_config/zsh/dot_zprofile) |

The version table and the reasoning behind each pin live in
[docs/shell.md](../../docs/shell.md#runtimes-mise).

## Why the hook is `run_after`, not `run_onchange`

`mise activate` puts tools on `PATH` but never installs a missing version, so
something has to download them. A `run_onchange_` hook keyed on `config.toml`
would only fire when the *declaration* changes — and a runtime can go missing
while the declaration stays put: a pruned `~/.local/share/mise`, a half-finished
first apply, a `latest` pin that has moved on. `run_after` re-converges every
apply instead, and the hook exits early and cheaply when there is nothing
missing.

That also means there is no recorded hash to freeze. The template hashes
`hook.sh` anyway, so the reason a hook re-runs is the same sentence for every
delegating hook in the repo rather than an exception to remember.

Nothing here fails an apply. mise absent (brew bundle has not finished yet) and
`mise install` failing (usually the network) both print the retry and exit 0 —
hooks 05 and 99 run after this one, and 99 prints the "Next moves" block a fresh
Mac depends on.

`BREW_BIN` overrides the hard-coded `/opt/homebrew/bin/brew` the hook uses to
put Homebrew on `PATH`. The path is absolute because chezmoi runs hooks without
a login shell; the override is what stops
[`tests/hook.bats`](tests/hook.bats) from being decided by whether the machine
running it happens to have mise installed.

## Two ways in, on purpose

Interactive shells get `mise activate` from `.zshrc`, which swaps the real
install dirs onto `PATH` on every `cd` — that is what makes per-project versions
and `JAVA_HOME` work. GUI apps never see it: macOS starts them from launchd, and
VS Code widens their `PATH` by resolving a *non-interactive login* zsh
(`.zshenv` + `.zprofile`, no `.zshrc`). So `.zprofile` also prepends mise's shim
dir, which needs no activate hook. Without it an editor's language servers get a
`PATH` with no JVM tooling on it and die on spawn.

Changing a runtime version therefore needs no editor change — but **an editor
already running must be fully quit and relaunched**, because the resolved
environment is captured once, at app start.

## Tests

[`tests/mise-config.bats`](tests/mise-config.bats) pins the global declarations
structurally, parsing the TOML rather than grepping it, because nothing else in
CI guards them: render-check only parses templates and lint-config only
validates syntax, so a runtime silently dropped while editing `config.toml`
would break per-project builds on the next apply and nothing would notice.
