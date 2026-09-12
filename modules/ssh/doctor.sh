#!/usr/bin/env bash
#
# The agent socket only exists once 1Password > Settings > Developer > "Use
# the SSH agent" is ticked, and the failure never mentions ssh config.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# Same literal as IdentityAgent in home/.ssh/config (tests/ssh.bats).
sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

# -S, not -e: an ordinary file at that path is not healthy.
if [[ -S $sock ]]; then
  ok ssh '1Password agent is live'
else
  warn ssh '1Password SSH agent is not running -- keys and signing will fail'
  dim 'enable it: 1Password > Settings > Developer > Use the SSH agent'
fi
