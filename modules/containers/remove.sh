#!/usr/bin/env bash
#
# The docker plugin links point into Homebrew's prefix, so the $DOT_ROOT sweep
# in uninstall.sh cannot see them.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# Not `die` without Homebrew: by now it may already be gone. But without the
# prefix no link can be PROVED ours, and these point outside $DOT_ROOT, so
# silence would leave them with nothing left to find them. Name them instead.
plugin_dir=''
if brew_load; then plugin_dir="$(brew --prefix)/lib/docker/cli-plugins"; fi

for plugin in docker-compose docker-buildx; do
  link="$HOME/.docker/cli-plugins/$plugin"
  [[ -L $link ]] || continue
  if [[ -z $plugin_dir ]]; then
    warn "left alone  ${link/#$HOME/\~} -- no Homebrew left to prove it is ours"
  # A link pointing elsewhere was put there by something else (Docker Desktop).
  elif [[ $(readlink "$link") == "$plugin_dir/"* ]]; then
    fs_unlink "$link"
  fi
done

# Tested BEFORE anything invokes colima: `colima status` creates ~/.colima on a
# machine that never had a VM. The profile directory, not ~/.colima itself,
# which this module's template link makes exist. doctor.sh tests the same path.
vm_on_disk=0
if [[ -d $HOME/.colima/default ]]; then vm_on_disk=1; fi

# Stopped, never deleted: the VM holds images and volumes.
if ((vm_on_disk)) && command -v colima >/dev/null 2>&1 && colima status >/dev/null 2>&1; then
  if [[ $DOT_DRY_RUN == 1 ]]; then
    info 'colima stop'
  else
    colima stop >/dev/null 2>&1 || warn 'colima would not stop; try: colima stop'
  fi
fi

if ((vm_on_disk)); then
  warn 'the colima VM is still on disk, with its images and volumes'
  dim 'Delete it yourself with: colima delete'
fi
