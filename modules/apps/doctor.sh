#!/usr/bin/env bash
#
# The gap every other check in this repo steps over: `brew bundle` is green the
# moment a cask lands on disk, and for a menu bar app that is barely half of
# being installed. Raycast with no hotkey bound is a fresh Mac's most confusing
# state -- the app is there, the Brewfile is satisfied, nothing is wrong, and
# the key you press does nothing.
#
# First launch is the evidence, not "is it running now": a machine where you
# quit Stats for an hour must not go yellow, and once macOS has written the
# preferences domain it stays written. Weaker than asking about the login item,
# which is the thing actually wanted -- but that lives in a database only root
# reads, and a check that needs sudo is a check nobody runs.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# An input, like DOT_BREW_BIN: without it the "not installed" branch is the one
# the machine running the tests never takes.
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
    warn "$app" "installed but never opened -- no $lost"
    dim "open -a $app, then turn on its own \"launch at login\""
  fi
done <"$data"
