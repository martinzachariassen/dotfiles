#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/defaults.tsv"

drift=()
check() {
  local domain=$1 key=$2 want=$4 got
  case "$3:$4" in
    bool:true) want=1 ;;
    bool:false) want=0 ;;
  esac
  got=$(defaults read "$domain" "$key" 2>/dev/null || echo '<unset>')
  if [[ $got != "$want" ]]; then drift+=("$domain $key is $got, expected $want"); fi
}

while IFS=$'\t' read -r domain key type value _; do
  if [[ -z $domain || $domain == '#'* ]]; then continue; fi
  check "$domain" "$key" "$type" "$value"
done <"$data"

dock_autohide=false
if module_setting_bool macos-defaults dock_autohide true; then dock_autohide=true; fi
check com.apple.dock autohide bool "$dock_autohide"

if ((${#drift[@]} == 0)); then
  ok defaults 'every managed key matches data/defaults.tsv'
else
  for row in "${drift[@]}"; do
    warn defaults "$row"
  done
  dim 'put them back with: dot apply'
fi

fw=${DOT_SOCKETFILTERFW:-/usr/libexec/ApplicationFirewall/socketfilterfw}

case $(fdesetup status 2>/dev/null) in
  *'FileVault is On'*) ok filevault 'on' ;;
  *'FileVault is Off'*)
    warn filevault 'off -- the disk is readable by anyone holding the machine'
    dim 'System Settings > Privacy & Security > FileVault'
    ;;
  *) warn filevault 'could not be read -- fdesetup did not answer' ;;
esac

if [[ -x $fw ]]; then
  case $("$fw" --getglobalstate 2>/dev/null) in
    *'State = 1'* | *'State = 2'*) ok firewall 'on' ;;
    *'State = 0'*)
      warn firewall 'off -- every listening port on this Mac is reachable'
      dim "turn it on: sudo $fw --setglobalstate on"
      ;;
    *) warn firewall 'could not be read -- socketfilterfw did not answer' ;;
  esac
else
  warn firewall "cannot be checked -- $fw is not there"
fi

su=${DOT_SOFTWAREUPDATE_PREFS:-/Library/Preferences/com.apple.SoftwareUpdate}
commerce=${DOT_COMMERCE_PREFS:-/Library/Preferences/com.apple.commerce}

unset_='<unset>' unreadable='<unreadable>'
# `defaults read` fails both for a key never written (its shipped default) and
# for a domain it cannot read; the plist on disk tells the two apart.
pref() {
  local value
  if value=$(defaults read "$1" "$2" 2>/dev/null); then
    printf '%s\n' "$value"
  elif [[ ! -e $3 ]] || defaults read "$1" >/dev/null 2>&1; then
    printf '%s\n' "$unset_"
  else
    printf '%s\n' "$unreadable"
  fi
}

flag() { pref "$1" "$2" "$1.plist"; }

su_off=() su_unknown=()
report() {
  case $2 in
    0) su_off+=("$1") ;;
    "$unreadable") su_unknown+=("$1") ;;
    *) ;;
  esac
}
report 'checks for updates' "$(flag "$su" AutomaticCheckEnabled)"
report 'downloads them' "$(flag "$su" AutomaticDownload)"
report 'installs security responses' "$(flag "$su" CriticalUpdateInstall)"
report 'installs XProtect and system data' "$(flag "$su" ConfigDataInstall)"
report 'updates App Store apps' "$(flag "$commerce" AutoUpdate)"

if ((${#su_off[@]} == 0 && ${#su_unknown[@]} == 0)); then
  ok updates 'checked, downloaded and security-patched automatically'
else
  for what in "${su_off[@]}"; do
    warn updates "macOS no longer $what"
  done
  for what in "${su_unknown[@]}"; do
    warn updates "could not be read -- whether macOS $what"
  done
  if ((${#su_off[@]})); then
    dim 'System Settings > General > Software Update > the (i) beside Automatic Updates'
  fi
fi

macos_auto=$(flag "$su" AutomaticallyInstallMacOSUpdates)
if [[ $macos_auto == "$unreadable" ]]; then
  warn updates 'could not be read -- whether macOS installs new versions on its own'
elif module_setting_bool macos-defaults macos_auto_update false; then
  case $macos_auto in
    0) warn updates 'macOS updates are not installed automatically, and macos_auto_update asks for that' ;;
    *) ok updates 'macOS updates install automatically' ;;
  esac
elif [[ $macos_auto == 0 ]]; then
  ok updates 'a new macOS version waits for you'
else
  warn updates 'macOS installs new versions on its own -- including major ones'
  dim "turn it off: sudo defaults write $su AutomaticallyInstallMacOSUpdates -bool false"
  dim 'the five switches above stay on; only the version bump becomes yours'
fi

want_browser=$(module_setting macos-defaults browser 'com.google.chrome')
if [[ -n $want_browser ]]; then
  ls_domain=com.apple.LaunchServices/com.apple.launchservices.secure
  handlers=$(pref "$ls_domain" LSHandlers \
    "$HOME/Library/Preferences/$ls_domain.plist")
  if [[ $handlers == "$unreadable" ]]; then
    warn browser 'could not be read -- LaunchServices did not answer'
  else
    if [[ $handlers == "$unset_" ]]; then handlers=''; fi
    # `role` resets at each array element, or an entry without LSHandlerRoleAll
    # inherits the previous entry's handler.
    if ! have_browser=$(printf '%s\n' "$handlers" |
      awk '/^[[:space:]]*\{[[:space:]]*$/{ role = "" }
           /LSHandlerRoleAll = /{ r = $0; sub(/.*= "?/, "", r); sub(/"?;$/, "", r); if (r != "-") role = r }
           /LSHandlerURLScheme = https/{ print role; exit }'); then
      warn browser 'could not be read -- the LaunchServices dump did not parse'
    elif [[ $have_browser == "$want_browser" ]]; then
      ok browser "$want_browser opens https links"
    elif [[ -z $have_browser ]]; then
      warn browser "https links still open in Safari, not $want_browser"
      dim "open $want_browser and accept its offer to become the default"
    else
      warn browser "https links open in $have_browser, and browser asks for $want_browser"
    fi
  fi
fi
