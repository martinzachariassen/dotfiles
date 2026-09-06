#!/usr/bin/env bash
#
# An OS update or a Settings pane reverts a value and says nothing; the only
# symptom is a Mac that behaves slightly wrong. This used to check six keys
# because each one cost a line. Reading the same file apply.sh writes from
# makes the whole table one loop, so nothing is sampled any more.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/defaults.tsv"

# check DOMAIN KEY TYPE VALUE -- `defaults read` prints booleans as 1/0 and
# everything else as written. The reading half of the TSV's type column;
# apply.sh is the writing half, with `-$type`.
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

# Not in the table because it follows a setting; normalised exactly as apply.sh
# normalises it before writing.
if module_setting_bool macos-defaults dock_autohide true; then
  check com.apple.dock autohide bool true
else
  check com.apple.dock autohide bool false
fi

# warn, not fail: an OS update reverting a key is not a broken install, and
# `dot apply` puts it back.
if ((${#drift[@]} == 0)); then
  ok 'defaults     every managed key matches data/defaults.tsv'
else
  for row in "${drift[@]}"; do
    warn "defaults     $row"
  done
  dim '             put them back with: dot apply'
fi
