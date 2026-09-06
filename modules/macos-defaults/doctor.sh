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
  ok 'defaults     every managed key matches data/defaults.tsv'
else
  for row in "${drift[@]}"; do
    warn "defaults     $row"
  done
  dim '             put them back with: dot apply'
fi
