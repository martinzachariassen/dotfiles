#!/usr/bin/env bash
#
# Merge this module's settings into ~/.claude/settings.json.
#
# The settings are data/settings.json, not a shell literal (modules/CLAUDE.md);
# all three hooks derive $want from it alike, and contract.bats proves it.
#
# Merged, never written whole: settings.json is the user's file. `. * $want`
# is a recursive merge, so every key this module does not name survives --
# including .permissions.allow, where an "Always allow" click lands.
#
# statusLine.command has to be absolute, so the data file carries `~/` and each
# hook expands it against $HOME. That keeps the file readable and machine-free.
#
# A managed key must be one only this repo sets. `/model` and the effort picker
# write back into this same file, so managing `model` or `effortLevel` turned
# doctor red the moment you switched and made the next apply revert it.
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.claude/settings.json"
data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/settings.json"
want=$(jq --arg home "$HOME" '.statusLine.command = $home + "/.claude/statusline.sh"' "$data")

if [[ $DOT_DRY_RUN == 1 ]]; then
  info "write   ~/.claude/settings.json ($(jq -r 'keys_unsorted | join(", ")' <<<"$want"))"
  exit 0
fi

mkdir -p "$(dirname "$dest")"
[[ -f $dest ]] || printf '{}\n' >"$dest"

# `jq -r type`, not `jq -e .`: -e reports `null` and `false` as unparseable,
# which they are not, and object is the real requirement anyway -- every jq
# program below indexes by key. All three hooks ask this same question.
kind=$(jq -r 'type' "$dest" 2>/dev/null) || kind='unparseable text'
if [[ $kind != object ]]; then
  fail "${dest/#$HOME/\~}: expected a JSON object, found $kind -- fix it or move it aside, then: dot apply"
  exit 1
fi

# chmod: mktemp is 0600 and `mv` carries that onto the destination, so a
# settings.json the user kept at 0644 came back private after every apply.
tmp="$(mktemp "${dest}.XXXXXX")"
chmod "$(stat -f '%Lp' "$dest")" "$tmp"

# `if`, never `jq ... && mv`: set -e ignores a non-final member of an && list,
# so a jq that died mid-merge printed the success line and exited 0. remove.sh
# guards the same way. The temp file is ours, so `rm` is right where a user's
# file would need fs_discard.
if jq --argjson want "$want" '. * $want' "$dest" >"$tmp" && mv "$tmp" "$dest"; then
  ok "Claude Code settings: $(jq -r 'keys_unsorted | length' <<<"$want") managed keys applied"
else
  rm -f "$tmp"
  fail "jq could not rewrite ${dest/#$HOME/\~} -- it was left as it was"
  exit 1
fi
