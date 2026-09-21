#!/usr/bin/env bash
#
# `brew bundle` is green the moment a cask lands on disk, and for a menu bar
# app that is half an installation: Raycast with no hotkey bound is a fresh
# Mac's most confusing state. Nothing else in the repo can see it.
#
# First launch is the evidence, not "is it running now": macOS writes the
# preferences domain the first time an app opens and never takes it back. See
# modules/apps/README.md.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# An input, so the "not installed" branch is reachable on a machine that has
# the apps.
apps_dir=${DOT_APPS_DIR:-/Applications}
data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/launch.tsv"

while IFS=$'\t' read -r app _ domain lost; do
  if [[ -z $app || $app == '#'* ]]; then continue; fi

  # Not installed says nothing. The cask may have been dropped on purpose, and
  # brew_missing already reports one that was not.
  if [[ ! -d $apps_dir/$app.app ]]; then continue; fi

  if [[ -e $HOME/Library/Preferences/$domain.plist ]]; then
    ok "$app" 'opened at least once'
  else
    # Column 4 completes "no ...", so it carries no article of its own;
    # tests/apps.bats holds the table to that.
    warn "$app" "installed but never opened -- no $lost"
    dim "open -a $app, then turn on its own \"launch at login\""
  fi
done <"$data"
