#!/usr/bin/env bash
#
# macOS preferences. Imperative and idempotent; nothing needs root.
#
# The writes are data/defaults.tsv, not shell literals: doctor.sh compares the
# same rows and remove.sh cuts the same domains, and all three find the file with
# the same `data=` line (tests/contract.bats). A value needing a config setting
# or validation stays here -- the file holds only what a reader could not refuse.
#
# Overrides live under [settings.macos-defaults].

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/defaults.tsv"

# One string, said by both branches, so a dry run and a real run print the same
# words. `dim`, not `warn`: true of every run that gets here, and as a warning it
# would exit DOT_STATUS_WARN every time and `dot apply` could never reach "Done".
relogin='log out and back in for keyboard and text-substitution changes to fully apply'

if [[ $DOT_DRY_RUN == 1 ]]; then
  info 'write macOS defaults (Dock, Finder, keyboard) and restart those apps'
  dim "$relogin"
  exit 0
fi

# --- the table --------------------------------------------------------------
while IFS=$'\t' read -r domain key type value _; do
  if [[ -z $domain || $domain == '#'* ]]; then continue; fi
  defaults write "$domain" "$key" "-$type" "$value"
done <"$data"

# --- values that come from config.toml ---------------------------------------
# Normalised to a literal true/false; doctor.sh reads the setting the same way.
dock_autohide=false
if module_setting_bool macos-defaults dock_autohide true; then dock_autohide=true; fi
defaults write com.apple.dock autohide -bool "$dock_autohide"

# `defaults -int` stores non-numeric as 0, and tilesize 0 is a Dock with no
# icons. fail, not die: one bad field must not cost the rest.
tilesize=$(module_setting macos-defaults dock_tilesize 48)
if [[ $tilesize =~ ^[0-9]+$ ]] && ((tilesize > 0)); then
  defaults write com.apple.dock tilesize -int "$tilesize"
else
  fail "dock_tilesize '$tilesize' is not a positive number -- left as it was"
fi

# Relative to $HOME unless absolute; a leading ~ is expanded, not taken literally.
screenshot_dir=$(module_setting macos-defaults screenshot_dir 'Pictures/Screenshots')
screenshot_dir=${screenshot_dir/#\~\//$HOME/}
[[ $screenshot_dir == /* ]] || screenshot_dir="$HOME/$screenshot_dir"
mkdir -p "$screenshot_dir"
defaults write com.apple.screencapture location -string "$screenshot_dir"

# --- Apply ------------------------------------------------------------------
# These read preferences at launch only. NSGlobalDomain needs a re-login.
for app in Dock Finder SystemUIServer WindowManager; do
  killall "$app" >/dev/null 2>&1 || true
done

ok 'macOS defaults written'
dim "$relogin"
