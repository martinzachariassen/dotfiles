#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if ! command -v colima >/dev/null 2>&1; then
  fail colima 'not installed (run: dot apply)'
# `colima status` creates ~/.colima/_lima when asked, so it is only asked once
# a VM exists.
elif [[ ! -d $HOME/.colima/default ]]; then
  warn colima 'no VM yet (create and start one with: colima start)'
elif colima status >/dev/null 2>&1; then
  ok colima 'running'
else
  warn colima 'not running (start it with: colima start)'
fi

colima_yaml="$HOME/.colima/default/colima.yaml"
if [[ -f $colima_yaml ]] && grep -qE '^[[:space:]]*sshConfig:[[:space:]]*true' "$colima_yaml"; then
  warn colima 'sshConfig is on -- `colima start` edits ~/.ssh/config, which is a link into this repo'
  dim 'turn it off: colima stop && colima start --ssh-config=false'
fi

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
