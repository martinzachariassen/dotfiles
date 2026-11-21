#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

mise_data=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}

if [[ -d $mise_data ]]; then
  warn 'left alone' "${mise_data/#$HOME/\~} -- language runtimes"
  dim 'Other projects resolve their toolchains from here. To remove it all:'
  dim '  mise implode'
fi
