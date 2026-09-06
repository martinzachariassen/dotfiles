#!/usr/bin/env bash
#
# `mise activate` never installs a runtime; linking config.toml alone leaves it
# unread until someone runs `mise install` by hand.
#
# Everything goes through `mise exec`: activation is a zsh hook (modules/zsh
# .zshrc) and hooks run under bash with no shell rc, so a bare `command -v go`
# is false on the machine this matters on -- the fresh one.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/go-tools.txt"

mapfile -t go_tools < <(grep -vE '^[[:space:]]*(#|$)' "$data")

if [[ $DOT_DRY_RUN == 1 ]]; then
  info 'mise install (runtimes pinned in ~/.config/mise/config.toml)'
  info "go install: ${#go_tools[@]} tools from data/go-tools.txt"
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
  ok "go: ${#go_tools[@]} tools installed"
else
  fail 'go is not installed by mise -- check the [tools] table in ~/.config/mise/config.toml'
fi
