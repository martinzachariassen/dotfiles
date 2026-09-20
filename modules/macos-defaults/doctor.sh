#!/usr/bin/env bash
#
# An OS update or a Settings pane reverts a value and says nothing; the only
# symptom is a Mac that behaves slightly wrong. Reading the same file apply.sh
# writes from makes the whole table one loop, so nothing is sampled.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/defaults.tsv"

# check DOMAIN KEY TYPE VALUE -- the reading half of the TSV's type column
# (apply.sh writes with `-$type`); `defaults read` prints a bool as 1/0.
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

# Not in the table because it follows a setting; normalised as apply.sh does.
dock_autohide=false
if module_setting_bool macos-defaults dock_autohide true; then dock_autohide=true; fi
check com.apple.dock autohide bool "$dock_autohide"

# warn, not fail: an OS update reverting a key is not a broken install.
if ((${#drift[@]} == 0)); then
  ok defaults 'every managed key matches data/defaults.tsv'
else
  for row in "${drift[@]}"; do
    warn defaults "$row"
  done
  dim 'put them back with: dot apply'
fi

# --- what this module can only report ---------------------------------------
#
# Three settings that are not `defaults` keys and never will be: each needs
# root to change and two need a GUI, so apply.sh cannot write them and the
# table must not pretend otherwise -- data/defaults.tsv is the list of what
# this module WRITES, and remove.sh derives its domain list from it.
#
# They live in this module anyway because it is the one for macOS system state,
# and a machine with the firewall off would otherwise be something nothing in
# this repo ever looks at. Reading all three needs no root and no unlock.
#
# The paths are inputs, like DOT_BREW_BIN: without them the branch a test needs
# is the one the machine running it never takes.
fw=${DOT_SOCKETFILTERFW:-/usr/libexec/ApplicationFirewall/socketfilterfw}
sudo_local=${DOT_SUDO_LOCAL:-/etc/pam.d/sudo_local}

# The one of the three that cannot be fixed after the laptop is gone.
case $(fdesetup status 2>/dev/null) in
  *'FileVault is On'*) ok filevault 'on' ;;
  *'FileVault is Off'*)
    warn filevault 'off -- the disk is readable by anyone holding the machine'
    dim 'System Settings > Privacy & Security > FileVault'
    ;;
  # Never silence: a question that could not be asked is not a healthy answer.
  *) warn filevault 'could not be read -- fdesetup did not answer' ;;
esac

if [[ -x $fw ]]; then
  # 1 is on; 2 is on and blocking every incoming connection. Only 0 is off.
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

# A taste rather than a baseline, so it has a setting the other two do not:
# a machine that does not want it must not stay yellow forever.
if module_setting_bool macos-defaults touch_id_sudo true; then
  # macOS ships sudo_local.template and no sudo_local, precisely because this
  # is a hand step. The template's pam_tid line is commented out, so the file
  # existing proves nothing -- an uncommented auth line is the whole evidence.
  if [[ -f $sudo_local ]] &&
    grep -qE '^[[:space:]]*auth[[:space:]].*pam_tid\.so' "$sudo_local"; then
    ok touch-id 'unlocks sudo'
  else
    warn touch-id 'does not unlock sudo'
    dim "add an uncommented pam_tid.so auth line to $sudo_local"
    dim "macOS ships the starting point at $sudo_local.template"
  fi
fi

# --- software update --------------------------------------------------------
#
# Reading /Library/Preferences needs no root; writing it does, which is why
# these are not rows in data/defaults.tsv either.
#
# They are split across six keys because macOS does not treat them as one
# switch, and neither should this: five are the ones you always want, and
# AutomaticallyInstallMacOSUpdates is the one that installs a whole new major
# version without being asked. Lumping them together is how a machine ends up
# a version ahead of where its owner meant to be, with the alternative being
# to turn security patches off to stop it.
#
# Inputs, like the two paths above: a domain under /Library/Preferences is not
# something a test may write, so without them the branches below are the ones
# the machine running the tests never takes.
su=${DOT_SOFTWAREUPDATE_PREFS:-/Library/Preferences/com.apple.SoftwareUpdate}
commerce=${DOT_COMMERCE_PREFS:-/Library/Preferences/com.apple.commerce}

# pref DOMAIN KEY PLIST -- the value, `<unset>` for a key that was never
# written, or `<unreadable>` when the read itself did not answer.
#
# `defaults read` exits non-zero for both, and collapsing them loses the
# three-state rule: every key here ships ON, so an absent one is a machine at
# its shipped default and must stay green, while a domain this process cannot
# read is a question that could not be asked and must warn. The plist beside
# the domain settles which -- a domain that exists but does not answer is the
# only one of the two that failed.
unset_='<unset>' unreadable='<unreadable>'
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

# flag DOMAIN KEY -- pref for the two domains named as absolute paths, whose
# plist is the path with .plist on the end.
flag() { pref "$1" "$2" "$1.plist"; }

# report WHAT VALUE -- the five that have one right answer.
su_off=() su_unknown=()
report() {
  case $2 in
    0) su_off+=("$1") ;;
    "$unreadable") su_unknown+=("$1") ;;
    *) ;; # 1, or unwritten and therefore at its shipped default
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

# The taste of the six, so it is a setting -- and the default is off, because
# the failure it prevents is the expensive one. A major version that arrives on
# its own cannot be undone without erasing the disk, while a minor patch it
# skips is a button you press when it suits you. Both branches are reachable,
# so neither is a machine nobody tested.
#
# Unwritten is ON here, the same reading `pref` gives the five above and for
# the same reason: this key ships on too. Only `0` is off, and everything else
# is a machine macOS may take to the next major version unasked -- including
# the fresh Mac whose owner never opened the pane, which is the one machine
# this check exists for and the one an "unwritten means off" would let pass.
# Unreadable is neither answer, in both branches of the setting.
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

# --- default browser --------------------------------------------------------
#
# Installing a browser and being sent to it are two things, and `apps` only
# does the first: every link on a fresh Mac opens in Safari until someone
# clicks through a confirmation sheet that no script may click for it.
#
# The setting is the escape hatch as well -- an empty one says nothing at all,
# which is what a machine that wants Safari sets.
want_browser=$(module_setting macos-defaults browser 'com.google.chrome')
if [[ -n $want_browser ]]; then
  # The LaunchServices database, and the plist that says whether it can be
  # read at all. A `|| true` here would turn a read that FAILED into "no
  # handler", which prints as a confident "still opens in Safari" for a
  # question nobody could ask -- and sends you to a sheet you already answered.
  #
  # An absent LSHandlers key is not that: it is a Mac on which nothing has ever
  # overridden a handler, which IS Safari and IS the fresh machine this check
  # exists for.
  ls_domain=com.apple.LaunchServices/com.apple.launchservices.secure
  handlers=$(pref "$ls_domain" LSHandlers \
    "$HOME/Library/Preferences/$ls_domain.plist")
  # `defaults` prints a dict's keys in alphabetical order, so LSHandlerRoleAll
  # always precedes the LSHandlerURLScheme it belongs to. The "-" guard drops
  # the one inside LSHandlerPreferredVersions, which sorts earlier still.
  #
  # `role` is cleared at each element of the array -- a bare `{` on its own
  # line, which a nested dict (`KEY = {`) is not. Without that, an https entry
  # carrying no LSHandlerRoleAll of its own would be answered with the previous
  # entry's handler: a confident wrong name is worse here than none, because
  # the wrong name reads as a browser you forgot installing.
  #
  # Printing an empty `role` and exiting is deliberate: $() strips the newline,
  # so a scheme with no handler lands in the "still opens in Safari" branch
  # rather than sending the scan on to some other entry's answer.
  if [[ $handlers == "$unreadable" ]]; then
    warn browser 'could not be read -- LaunchServices did not answer'
  else
    if [[ $handlers == "$unset_" ]]; then handlers=''; fi
    if ! have_browser=$(printf '%s\n' "$handlers" |
      awk '/^[[:space:]]*\{[[:space:]]*$/{ role = "" }
           /LSHandlerRoleAll = /{ r = $0; sub(/.*= "?/, "", r); sub(/"?;$/, "", r); if (r != "-") role = r }
           /LSHandlerURLScheme = https/{ print role; exit }'); then
      # A dump that arrived and did not parse is the third state too: the shape
      # of this output is `defaults`' own, and it has changed before.
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
