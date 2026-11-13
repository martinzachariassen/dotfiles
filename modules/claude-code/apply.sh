#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.claude/settings.json"
data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/settings.json"
want=$(jq --arg home "$HOME" '.statusLine.command = $home + "/.claude/statusline.sh"' "$data")

if [[ $DOT_DRY_RUN == 1 ]]; then
  info write "${dest/#$HOME/\~} ($(jq -r 'keys_unsorted | join(", ")' <<<"$want"))"
  exit 0
fi

mkdir -p "$(dirname "$dest")"
[[ -f $dest ]] || printf '{}\n' >"$dest"

# `jq -r type`, not `jq -e .`: -e reports `null` and `false` as unparseable.
kind=$(jq -r 'type' "$dest" 2>/dev/null) || kind='unparseable text'
if [[ $kind != object ]]; then
  fail settings "${dest/#$HOME/\~} is $kind, not a JSON object -- fix it or move it aside, then: dot apply"
  exit 1
fi

tmp="$(mktemp "${dest}.XXXXXX")"
# mktemp creates 0600, and `mv` would carry that onto the user's file.
chmod "$(stat -f '%Lp' "$dest")" "$tmp"

# `if`, never `jq ... && mv` alone: set -e ignores a non-final member of an
# && list, so a jq that dies mid-merge would report success.
if jq --argjson want "$want" '. * $want' "$dest" >"$tmp" && mv "$tmp" "$dest"; then
  ok settings "$(jq -r 'keys_unsorted | length' <<<"$want") managed keys applied"
else
  rm -f "$tmp"
  fail settings "jq could not rewrite ${dest/#$HOME/\~} -- it was left as it was"
  exit 1
fi
