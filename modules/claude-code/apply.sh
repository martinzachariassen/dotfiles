#!/usr/bin/env bash
#
# Merge this module's settings into ~/.claude/settings.json.
#
# `. * $want` is a recursive merge, so every key this module does not name
# survives -- including .permissions.allow, where an "Always allow" click lands.
# statusLine.command must be absolute, so data/settings.json carries `~/` and
# each hook expands it against $HOME.
#
# Manage only keys nothing else writes: `/model` and the effort picker write
# back into this file, so managing those would fight the user on every apply.
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

# `jq -r type`, not `jq -e .`: -e reports `null` and `false` as unparseable,
# and object is the real requirement anyway. All three hooks ask this question.
kind=$(jq -r 'type' "$dest" 2>/dev/null) || kind='unparseable text'
if [[ $kind != object ]]; then
  fail settings "${dest/#$HOME/\~} is $kind, not a JSON object -- fix it or move it aside, then: dot apply"
  exit 1
fi

# chmod: mktemp is 0600 and `mv` carries that onto the destination, so a
# settings.json the user kept at 0644 came back private after every apply.
tmp="$(mktemp "${dest}.XXXXXX")"
chmod "$(stat -f '%Lp' "$dest")" "$tmp"

# `if`, never `jq ... && mv`: set -e ignores a non-final member of an && list,
# so a jq that dies mid-merge prints the success line and exits 0. The temp file
# is ours, so `rm` is right where a user's file would need fs_discard.
if jq --argjson want "$want" '. * $want' "$dest" >"$tmp" && mv "$tmp" "$dest"; then
  ok settings "$(jq -r 'keys_unsorted | length' <<<"$want") managed keys applied"
else
  rm -f "$tmp"
  fail settings "jq could not rewrite ${dest/#$HOME/\~} -- it was left as it was"
  exit 1
fi
