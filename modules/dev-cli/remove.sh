#!/usr/bin/env bash
#
# Reports, never deletes, and stays silent with no tree: see README.md,
# "Removal deletes nothing".

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# mise's own default resolution, which it does not expose for scripting and
# which has to keep working once mise itself is gone. Same line as doctor.sh
# (tests/contract.bats).
mise_data=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}

if [[ -d $mise_data ]]; then
  warn 'left alone' "${mise_data/#$HOME/\~} -- language runtimes"
  dim 'Other projects resolve their toolchains from here. To remove it all:'
  dim '  mise implode'
fi
