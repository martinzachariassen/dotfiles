#!/usr/bin/env bash
#
# Undo apply.sh. Only leaves whose value is still exactly what this module
# wrote are removed; anything changed since is left standing, and an object
# this module emptied (.permissions) goes with them. statusline.sh and the
# theme are home/ symlinks and go with the generic sweep.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.claude/settings.json"
data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/settings.json"
want=$(jq --arg home "$HOME" '.statusLine.command = $home + "/.claude/statusline.sh"' "$data")

[[ -f $dest ]] || exit 0

if ! jq -e . "$dest" >/dev/null 2>&1; then
  warn 'left alone  ~/.claude/settings.json is not valid JSON'
  exit "$DOT_STATUS_WARN"
fi

if [[ $DOT_DRY_RUN == 1 ]]; then
  info "remove  this module's keys from ~/.claude/settings.json"
  exit 0
fi

# Must match doctor.sh (tests/contract.bats). objs() prunes only the objects
# this module itself emptied -- deepest first, so a parent sees its child gone.
tmp="$(mktemp "${dest}.XXXXXX")"
jq --argjson want "$want" '
  def leaves($p): to_entries[] | ($p + [.key]) as $q | if (.value|type) == "object" then (.value|leaves($q)) else $q end;
  def objs($p):   to_entries[] | ($p + [.key]) as $q | if (.value|type) == "object" then $q, (.value|objs($q)) else empty end;
  reduce ($want | leaves([])) as $p (.; if getpath($p) == ($want|getpath($p)) then delpaths([$p]) else . end)
  | reduce ([$want | objs([])] | sort_by(length) | reverse | .[]) as $p (.; if getpath($p) == {} then delpaths([$p]) else . end)
' "$dest" >"$tmp" && mv "$tmp" "$dest"

ok "removed this module's keys from ~/.claude/settings.json"
