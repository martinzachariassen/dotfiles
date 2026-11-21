#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

apps_dir=${DOT_APPS_DIR:-/Applications}
data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/launch.tsv"

while IFS=$'\t' read -r app _ domain lost; do
  if [[ -z $app || $app == '#'* ]]; then continue; fi

  if [[ ! -d $apps_dir/$app.app ]]; then continue; fi

  if [[ -e $HOME/Library/Preferences/$domain.plist ]]; then
    ok "$app" 'opened at least once'
  else
    warn "$app" "installed but never opened -- no $lost"
    dim "open -a $app, then turn on its own \"launch at login\""
  fi
done <"$data"
