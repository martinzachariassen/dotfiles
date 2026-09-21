#!/usr/bin/env bash
#
# The agent socket only exists once 1Password > Settings > Developer > "Use
# the SSH agent" is ticked, and the failure never mentions ssh config.
#
# Two questions, not one: whether the agent is there, and whether it holds a
# key. A locked vault serves a live socket and no identities, which is a
# machine that cannot push and reads as healthy.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# Same literal as IdentityAgent in home/.ssh/config (tests/ssh.bats).
sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

# An input, so the no-keys branch is reachable on a developer machine with an
# unlocked vault.
ssh_add=${DOT_SSH_ADD:-ssh-add}

# -S, not -e: an ordinary file at that path is not healthy.
if [[ ! -S $sock ]]; then
  warn ssh '1Password SSH agent is not running -- keys and signing will fail'
  dim 'enable it: 1Password > Settings > Developer > Use the SSH agent'
  exit 0
fi

# Listing is not signing: the agent answers a key list without raising a
# 1Password approval dialog, which is what makes this allowed in a read-only
# check. Never `ssh-add -T` or anything that signs.
#
# ssh-add's three exit codes are three different machines: 0 listed keys, 1 an
# agent holding none, 2 an agent that could not be reached at all.
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
