#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

plugin_dir=''
if brew_load; then plugin_dir="$(brew --prefix)/lib/docker/cli-plugins"; fi

for plugin in docker-compose docker-buildx; do
  link="$HOME/.docker/cli-plugins/$plugin"
  [[ -L $link ]] || continue
  if [[ -z $plugin_dir ]]; then
    warn 'left alone' "${link/#$HOME/\~} -- no Homebrew left to prove it is ours"
  elif [[ $(readlink "$link") == "$plugin_dir/"* ]]; then
    fs_unlink "$link"
  fi
done

vm_on_disk=0
# Tested before anything invokes colima: `colima status` creates ~/.colima/_lima.
if [[ -d $HOME/.colima/default ]]; then vm_on_disk=1; fi

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
