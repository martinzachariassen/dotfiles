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
