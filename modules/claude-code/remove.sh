#!/usr/bin/env bash
#
# Undo apply.sh. Only leaves still holding exactly what this module wrote are
# removed; anything changed since stands, and an object this module emptied
# (.permissions) goes too. statusline.sh and the theme are home/ symlinks.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.claude/settings.json"
data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/settings.json"

# Both guards come before $want, the first line that runs jq: uninstall.sh
# calls every remove.sh, enabled or not, and jq comes from this module's own
# Brewfile.
[[ -f $dest ]] || exit 0
command -v jq >/dev/null 2>&1 || {
  warn 'left alone' "${dest/#$HOME/\~} -- jq is not installed"
  exit "$DOT_STATUS_WARN"
}

want=$(jq --arg home "$HOME" '.statusLine.command = $home + "/.claude/statusline.sh"' "$data")

# The same question apply.sh and doctor.sh ask, for the same reason.
kind=$(jq -r 'type' "$dest" 2>/dev/null) || kind='unparseable text'
if [[ $kind != object ]]; then
  warn 'left alone' "${dest/#$HOME/\~} is $kind, not a JSON object"
  exit "$DOT_STATUS_WARN"
fi

if [[ $DOT_DRY_RUN == 1 ]]; then
  info remove "this module's keys from ~/.claude/settings.json"
  exit 0
fi

# Must match doctor.sh (tests/contract.bats). objs() prunes only the objects
# this module itself emptied -- deepest first, so a parent sees its child gone.
# chmod: mktemp is 0600 and `mv` carries that onto the destination.
tmp="$(mktemp "${dest}.XXXXXX")"
chmod "$(stat -f '%Lp' "$dest")" "$tmp"

# `if`, never `jq ... && mv`: set -e ignores a non-final member of an && list.
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
