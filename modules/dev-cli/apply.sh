#!/usr/bin/env bash
#
# `mise activate` never installs a runtime; linking config.toml alone leaves it
# unread until someone runs `mise install` by hand.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if [[ $DOT_DRY_RUN == 1 ]]; then
  info mise 'install the runtimes locked in ~/.config/mise/mise.lock'
  exit 0
fi

# Guarded like module_apply itself: brew_bundle failing leaves no mise, and
# module_apply only skips apply.sh when the Brewfile itself reported failure.
if ! command -v mise >/dev/null 2>&1; then
  fail mise 'not installed -- its Brewfile line did not apply. Run: dot apply'
  exit 1
fi

# --locked: a tool the lock does not name fails rather than resolving `latest` here.
mise install --locked --yes 2>&1 | ui_quote
ok mise 'runtimes installed'
