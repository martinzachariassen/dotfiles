#!/usr/bin/env bash
#
# A stopped VM makes every docker command fail with an error that names a
# socket rather than the reason.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# `colima status` is NOT read-only: it creates ~/.colima/_lima on a machine that
# never started a VM. Only asked once the profile directory exists -- not
# ~/.colima, which this module's template link makes exist. remove.sh agrees.
if ! command -v colima >/dev/null 2>&1; then
  fail 'colima       not installed (run: dot apply)'
elif [[ ! -d $HOME/.colima/default ]]; then
  warn 'colima       no VM yet (create and start one with: colima start)'
elif colima status >/dev/null 2>&1; then
  ok 'colima       running'
else
  warn 'colima       not running (start it with: colima start)'
fi

# With sshConfig on, every `colima start` prepends an Include to ~/.ssh/config,
# which is a link into this repo. fs_check_tree sees a correct link, not its
# contents, so only this check can catch it.
colima_yaml="$HOME/.colima/default/colima.yaml"
if [[ -f $colima_yaml ]] && grep -qE '^[[:space:]]*sshConfig:[[:space:]]*true' "$colima_yaml"; then
  warn 'colima       sshConfig is on -- `colima start` edits ~/.ssh/config, which is a link into this repo'
  dim '             turn it off: colima stop && colima start --ssh-config=false'
fi
