#!/usr/bin/env bash
#
# Drift here is invisible -- a broken statusLine renders nothing, a changed
# theme says nothing at all -- so every managed leaf is compared, not sampled.
# Fair only because apply.sh manages no key Claude Code writes back.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

command -v jq >/dev/null 2>&1 || {
  fail 'jq is not installed -- statusline.sh and this module depend on it (run: dot apply)'
  exit 1
}

dest="$HOME/.claude/settings.json"
data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/settings.json"
want=$(jq --arg home "$HOME" '.statusLine.command = $home + "/.claude/statusline.sh"' "$data")

if [[ ! -f $dest ]]; then
  fail 'settings     ~/.claude/settings.json does not exist -- run: dot apply'
elif [[ $(jq -r 'type' "$dest" 2>/dev/null) != object ]]; then
  fail 'settings     ~/.claude/settings.json is not a JSON object -- fix it, then run: dot apply'
else
  # Leaves, not top-level keys: .permissions.defaultMode is ours, .permissions
  # as a whole is not. Must match remove.sh (tests/contract.bats).
  drift=$(jq -r --argjson want "$want" '
    def leaves($p): to_entries[] | ($p + [.key]) as $q | if (.value|type) == "object" then (.value|leaves($q)) else $q end;
    . as $have | $want | leaves([]) | . as $p
    | select(($have|getpath($p)) != ($want|getpath($p))) | $p | join(".")' "$dest")

  if [[ -z $drift ]]; then
    ok 'settings     every managed key matches data/settings.json'
  else
    while IFS= read -r key; do
      fail "settings     .$key differs from data/settings.json -- run: dot apply"
    done <<<"$drift"
  fi
fi
