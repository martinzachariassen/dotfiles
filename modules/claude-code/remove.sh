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

# Both guards come before $want, which is the first line that runs jq.
# uninstall.sh calls every module's remove.sh, enabled or not, and jq is
# installed by this module's own Brewfile: on a machine that never enabled
# claude-code, computing $want first made the whole uninstall unrunnable.
[[ -f $dest ]] || exit 0
command -v jq >/dev/null 2>&1 || {
  warn 'left alone  ~/.claude/settings.json -- jq is not installed'
  exit "$DOT_STATUS_WARN"
}

want=$(jq --arg home "$HOME" '.statusLine.command = $home + "/.claude/statusline.sh"' "$data")

# The same question apply.sh and doctor.sh ask, for the same reason.
kind=$(jq -r 'type' "$dest" 2>/dev/null) || kind='unparseable text'
if [[ $kind != object ]]; then
  warn "left alone  ~/.claude/settings.json: expected a JSON object, found $kind"
  exit "$DOT_STATUS_WARN"
fi

if [[ $DOT_DRY_RUN == 1 ]]; then
  info "remove  this module's keys from ~/.claude/settings.json"
  exit 0
fi

# Must match doctor.sh (tests/contract.bats). objs() prunes only the objects
# this module itself emptied -- deepest first, so a parent sees its child gone.
# chmod: mktemp is 0600 and `mv` carries that onto the destination, so a
# settings.json the user kept at 0644 came back private. apply.sh does the same.
tmp="$(mktemp "${dest}.XXXXXX")"
chmod "$(stat -f '%Lp' "$dest")" "$tmp"

# `if`, never `jq ... && mv`: set -e ignores a non-final member of an && list,
# so a jq that died mid-rewrite printed the success line below, exited 0, and
# left the temp file in ~/.claude.
if jq --argjson want "$want" '
  def leaves($p): to_entries[] | ($p + [.key]) as $q | if (.value|type) == "object" then (.value|leaves($q)) else $q end;
  def objs($p):   to_entries[] | ($p + [.key]) as $q | if (.value|type) == "object" then $q, (.value|objs($q)) else empty end;
  reduce ($want | leaves([])) as $p (.; if getpath($p) == ($want|getpath($p)) then delpaths([$p]) else . end)
  | reduce ([$want | objs([])] | sort_by(length) | reverse | .[]) as $p (.; if getpath($p) == {} then delpaths([$p]) else . end)
' "$dest" >"$tmp" && mv "$tmp" "$dest"; then
  ok "removed this module's keys from ~/.claude/settings.json"
else
  rm -f "$tmp"
  warn 'left alone  ~/.claude/settings.json -- jq could not rewrite it'
  exit "$DOT_STATUS_WARN"
fi
