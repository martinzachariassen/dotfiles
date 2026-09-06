#!/usr/bin/env bash
#
# Merge this module's settings into ~/.claude/settings.json.
#
# The settings are data/settings.json, not a shell literal: it is the file you
# read to know what this module asserts, jq consumes it directly, and
# contract.bats validates it as JSON like every other shipped data file. All
# three hooks derive $want from it with the same two lines -- contract.bats
# asserts the copies agree, so there is one statement of the truth.
#
# Merged, never written whole: settings.json is the user's file. `. * $want`
# is a recursive merge, so every key this module does not name survives --
# including .permissions.allow, where an "Always allow" click lands.
#
# statusLine.command has to be absolute, so the data file carries `~/` and each
# hook expands it against $HOME. That keeps the file readable and machine-free.
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

# jq would exit non-zero and leave the file as it was -- correct, but the
# reason never reaches the summary. Name it, and say what to do about it.
if ! jq -e . "$dest" >/dev/null 2>&1; then
  fail "${dest/#$HOME/\~} is not valid JSON -- fix it or move it aside, then: dot apply"
  exit 1
fi

tmp="$(mktemp "${dest}.XXXXXX")"
jq --argjson want "$want" '. * $want' "$dest" >"$tmp" && mv "$tmp" "$dest"

ok "Claude Code settings: $(jq -r 'keys_unsorted | length' <<<"$want") managed keys applied"
