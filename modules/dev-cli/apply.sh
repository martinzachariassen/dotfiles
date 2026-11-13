#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if [[ $DOT_DRY_RUN == 1 ]]; then
  info mise 'install the runtimes locked in ~/.config/mise/mise.lock'
  exit 0
fi

if ! command -v mise >/dev/null 2>&1; then
  fail mise 'not installed -- its Brewfile line did not apply. Run: dot apply'
  exit 1
fi

mise install --locked --yes 2>&1 | ui_quote
ok mise 'runtimes installed'
