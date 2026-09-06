#!/usr/bin/env bash
#
# `mise activate` never installs a runtime; linking config.toml alone leaves it
# unread until someone runs `mise install` by hand.
#
# gopls/dlv/goimports/staticcheck aren't runtimes mise tracks -- they're
# `go install` binaries VS Code's Go extension needs for IntelliSense,
# debugging, format-on-save and linting. `go install` recompiles from
# module cache each run, so this stays cheap on a re-apply.
#
# Everything goes through `mise exec`: activation is a zsh hook (modules/zsh
# .zshrc), and hooks run under bash with no shell rc. A bare `command -v go`
# here is false on the machine this matters on -- the fresh one, installed by
# `curl | bash` -- so the tools were silently skipped until the second apply
# from an interactive shell.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

go_tools=(
  golang.org/x/tools/gopls@latest
  github.com/go-delve/delve/cmd/dlv@latest
  golang.org/x/tools/cmd/goimports@latest
  honnef.co/go/tools/cmd/staticcheck@latest
)

if [[ $DOT_DRY_RUN == 1 ]]; then
  info 'mise install (runtimes pinned in ~/.config/mise/config.toml)'
  info 'go install: gopls, dlv, goimports, staticcheck'
  exit 0
fi

# Guarded like the go step below it: brew_bundle failing leaves no mise, and
# module_apply only skips apply.sh when the Brewfile itself reported failure.
if ! command -v mise >/dev/null 2>&1; then
  fail 'mise is not installed -- its Brewfile line did not apply. Run: dot apply'
  exit 1
fi

mise install --yes
ok 'mise: runtimes installed'

# `mise exec -- go` rather than `go`: mise owns the toolchain and sets GOBIN
# into its own install dir, so the binaries land where an activated shell
# already looks.
if mise exec -- go version >/dev/null 2>&1; then
  for pkg in "${go_tools[@]}"; do
    if ! mise exec -- go install "$pkg"; then
      fail "go install $pkg failed -- re-run \`dot apply\` once the network is back"
    fi
  done
  ok 'go: gopls, dlv, goimports, staticcheck installed'
else
  fail 'go is not installed by mise -- check the [tools] table in ~/.config/mise/config.toml'
fi
