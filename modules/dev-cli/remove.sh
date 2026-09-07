#!/usr/bin/env bash
#
# Nothing to delete, and that is the point: apply.sh downloads into directories
# full of other projects' toolchains, so this reports what is left rather than
# guessing which of it was ours. Same trade as macos-defaults -- no state file,
# so the warning is the deliverable.
#
# Silent when the directory does not exist: uninstall.sh runs every module's
# remove.sh, and a machine that never enabled dev-cli must hear nothing.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# mise's own default resolution, which it does not expose for scripting and
# which has to keep working once mise itself is gone. Same line as doctor.sh
# (tests/contract.bats).
mise_data=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}

if [[ -d $mise_data ]]; then
  warn "left alone  ${mise_data/#$HOME/\~} -- language runtimes"
  dim 'Other projects resolve their toolchains from here. To remove it all:'
  dim '  mise implode'
fi
