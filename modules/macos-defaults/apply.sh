#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/defaults.tsv"

relogin='log out and back in for keyboard and text-substitution changes to fully apply'

if [[ $DOT_DRY_RUN == 1 ]]; then
  info defaults 'write the Dock, Finder, input and screenshot keys, and restart those apps'
  dim "$relogin"
  exit 0
fi

while IFS=$'\t' read -r domain key type value _; do
  if [[ -z $domain || $domain == '#'* ]]; then continue; fi
  defaults write "$domain" "$key" "-$type" "$value"
done <"$data"

dock_autohide=false
if module_setting_bool macos-defaults dock_autohide true; then dock_autohide=true; fi
defaults write com.apple.dock autohide -bool "$dock_autohide"

tilesize=$(module_setting macos-defaults dock_tilesize 48)
# `defaults -int` stores non-numeric as 0, and tilesize 0 is a Dock with no icons.
if [[ $tilesize =~ ^[0-9]+$ ]] && ((tilesize > 0)); then
  defaults write com.apple.dock tilesize -int "$tilesize"
else
  fail defaults "dock_tilesize '$tilesize' is not a positive number -- left as it was"
fi

screenshot_dir=$(module_setting macos-defaults screenshot_dir 'Pictures/Screenshots')
screenshot_dir=${screenshot_dir/#\~\//$HOME/}
[[ $screenshot_dir == /* ]] || screenshot_dir="$HOME/$screenshot_dir"
mkdir -p "$screenshot_dir"
defaults write com.apple.screencapture location -string "$screenshot_dir"

for app in Dock Finder SystemUIServer WindowManager; do
  killall "$app" >/dev/null 2>&1 || true
done

if ((DOT_FAILURES == 0)); then ok defaults 'written'; fi
dim "$relogin"
