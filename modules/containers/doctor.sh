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
  fail colima 'not installed (run: dot apply)'
elif [[ ! -d $HOME/.colima/default ]]; then
  warn colima 'no VM yet (create and start one with: colima start)'
elif colima status >/dev/null 2>&1; then
  ok colima 'running'
else
  warn colima 'not running (start it with: colima start)'
fi

# With sshConfig on, every `colima start` prepends an Include to ~/.ssh/config,
# which is a link into this repo. fs_check_tree sees a correct link, not its
# contents, so only this check can catch it.
colima_yaml="$HOME/.colima/default/colima.yaml"
if [[ -f $colima_yaml ]] && grep -qE '^[[:space:]]*sshConfig:[[:space:]]*true' "$colima_yaml"; then
  warn colima 'sshConfig is on -- `colima start` edits ~/.ssh/config, which is a link into this repo'
  dim 'turn it off: colima stop && colima start --ssh-config=false'
fi

# DOCKER_HOST and TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE come from ~/.zshenv
# (the zsh module), computed fresh on every shell start -- so a process that
# predates the link just hasn't opened a new shell yet, the same reasoning as
# core/doctor.sh's PATH check.
if [[ -d $HOME/.colima/default ]]; then
  want_host="unix://$HOME/.colima/default/docker.sock"
  want_override='/var/run/docker.sock'
  if [[ ${DOCKER_HOST:-} == "$want_host" && ${TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE:-} == "$want_override" ]]; then
    ok DOCKER_HOST 'set for Testcontainers'
  elif [[ -L $HOME/.zshenv ]]; then
    dim DOCKER_HOST 'arrives with your next shell'
  else
    warn DOCKER_HOST 'not set -- Testcontainers cannot find Docker (enable the zsh module)'
  fi
fi
