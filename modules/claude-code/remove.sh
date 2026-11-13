#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.claude/settings.json"
data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/settings.json"

[[ -f $dest ]] || exit 0
# Before the first jq: uninstall.sh runs every remove.sh, enabled or not, and
# jq comes from this module's own Brewfile.
command -v jq >/dev/null 2>&1 || {
  warn 'left alone' "${dest/#$HOME/\~} -- jq is not installed"
  exit "$DOT_STATUS_WARN"
}

want=$(jq --arg home "$HOME" '.statusLine.command = $home + "/.claude/statusline.sh"' "$data")

kind=$(jq -r 'type' "$dest" 2>/dev/null) || kind='unparseable text'
if [[ $kind != object ]]; then
  warn 'left alone' "${dest/#$HOME/\~} is $kind, not a JSON object"
  exit "$DOT_STATUS_WARN"
fi

if [[ $DOT_DRY_RUN == 1 ]]; then
  info remove "this module's keys from ~/.claude/settings.json"
  exit 0
fi

tmp="$(mktemp "${dest}.XXXXXX")"
chmod "$(stat -f '%Lp' "$dest")" "$tmp"

if jq --argjson want "$want" '
  def leaves($p): to_entries[] | ($p + [.key]) as $q | if (.value|type) == "object" then (.value|leaves($q)) else $q end;
  def objs($p):   to_entries[] | ($p + [.key]) as $q | if (.value|type) == "object" then $q, (.value|objs($q)) else empty end;
  reduce ($want | leaves([])) as $p (.; if getpath($p) == ($want|getpath($p)) then delpaths([$p]) else . end)
  | reduce ([$want | objs([])] | sort_by(length) | reverse | .[]) as $p (.; if getpath($p) == {} then delpaths([$p]) else . end)
' "$dest" >"$tmp" && mv "$tmp" "$dest"; then
  ok removed "this module's keys from ~/.claude/settings.json"
else
  rm -f "$tmp"
  warn 'left alone' "${dest/#$HOME/\~} -- jq could not rewrite it"
  exit "$DOT_STATUS_WARN"
fi
