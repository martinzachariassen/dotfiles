#!/usr/bin/env bash
#
# `mise activate` never installs a runtime; linking config.toml alone leaves it
# unread until someone runs `mise install` by hand.
#
# gopls/dlv/goimports/staticcheck aren't runtimes mise tracks -- they're
# `go install` binaries VS Code's Go extension needs for IntelliSense,
# debugging, format-on-save and linting. `go install` recompiles from
# module cache each run, so this stays cheap on a re-apply.

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

mise install --yes
ok 'mise: runtimes installed'

if command -v go >/dev/null 2>&1; then
  for pkg in "${go_tools[@]}"; do
    go install "$pkg"
  done
  ok 'go: gopls, dlv, goimports, staticcheck installed'
else
  warn 'go is not on PATH -- skipping gopls/dlv/goimports/staticcheck'
fi
