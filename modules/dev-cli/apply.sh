#!/usr/bin/env bash
#
# `mise activate` never installs a runtime; linking config.toml alone leaves it
# unread until someone runs `mise install` by hand.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if [[ $DOT_DRY_RUN == 1 ]]; then
  info 'mise install (runtimes pinned in ~/.config/mise/config.toml)'
  exit 0
fi

# Guarded like module_apply itself: brew_bundle failing leaves no mise, and
# module_apply only skips apply.sh when the Brewfile itself reported failure.
if ! command -v mise >/dev/null 2>&1; then
  fail 'mise is not installed -- its Brewfile line did not apply. Run: dot apply'
  exit 1
fi

mise install --yes
ok 'mise: runtimes installed'
