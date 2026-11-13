#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

ssh_add=${DOT_SSH_ADD:-ssh-add}

if [[ ! -S $sock ]]; then
  warn ssh '1Password SSH agent is not running -- keys and signing will fail'
  dim 'enable it: 1Password > Settings > Developer > Use the SSH agent'
  exit 0
fi

# Listing keys never signs, so it raises no 1Password dialog. Never `ssh-add -T`.
keys=$(SSH_AUTH_SOCK="$sock" "$ssh_add" -l 2>/dev/null) && status=0 || status=$?
case $status in
  0) ok ssh "1Password agent is live ($(grep -c . <<<"$keys") key(s))" ;;
  1)
    warn ssh '1Password agent holds no keys -- pushes and signing will fail'
    dim 'unlock 1Password, or tick the key under 1Password > Settings > Developer'
    dim 'a key outside the vault in ~/.config/1Password/ssh/agent.toml is never offered'
    ;;
  *)
    warn ssh "1Password agent did not answer -- $ssh_add could not reach the socket"
    dim 'quit and reopen 1Password'
    ;;
esac
