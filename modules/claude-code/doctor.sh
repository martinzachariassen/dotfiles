#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

command -v jq >/dev/null 2>&1 || {
  fail jq 'not installed -- statusline.sh and this module depend on it (run: dot apply)'
  exit 1
}

dest="$HOME/.claude/settings.json"
data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/settings.json"
want=$(jq --arg home "$HOME" '.statusLine.command = $home + "/.claude/statusline.sh"' "$data")

if [[ ! -f $dest ]]; then
  fail settings "${dest/#$HOME/\~} does not exist -- run: dot apply"
elif [[ $(jq -r 'type' "$dest" 2>/dev/null) != object ]]; then
  fail settings "${dest/#$HOME/\~} is not a JSON object -- fix it, then run: dot apply"
else
  drift=$(jq -r --argjson want "$want" '
    def leaves($p): to_entries[] | ($p + [.key]) as $q | if (.value|type) == "object" then (.value|leaves($q)) else $q end;
    . as $have | $want | leaves([]) | . as $p
    | select(($have|getpath($p)) != ($want|getpath($p))) | $p | join(".")' "$dest")

  if [[ -z $drift ]]; then
    ok settings 'every managed key matches data/settings.json'
  else
    while IFS= read -r key; do
      fail settings ".$key differs from data/settings.json -- run: dot apply"
    done <<<"$drift"
  fi
fi

keychain=${DOT_CLAUDE_KEYCHAIN:-Claude Code-credentials}

if module_setting_bool claude-code auth_check true; then
  if [[ -n ${ANTHROPIC_API_KEY:-} ]]; then
    ok auth 'ANTHROPIC_API_KEY is set'
  elif [[ -n ${ANTHROPIC_AUTH_TOKEN:-} ]]; then
    ok auth 'ANTHROPIC_AUTH_TOKEN is set'
  elif [[ -n ${CLAUDE_CODE_USE_BEDROCK:-} && ${CLAUDE_CODE_USE_BEDROCK:-0} != 0 ]]; then
    ok auth 'pointed at Bedrock, which brings its own credentials'
  elif [[ -n ${CLAUDE_CODE_USE_VERTEX:-} && ${CLAUDE_CODE_USE_VERTEX:-0} != 0 ]]; then
    ok auth 'pointed at Vertex AI, which brings its own credentials'
  # Attributes only, never `-w`: reading the secret raises a keychain dialog, and
  # a read-only check may not block on a human.
  elif security find-generic-password -s "$keychain" >/dev/null 2>&1; then
    ok auth 'signed in'
  else
    warn auth 'never signed in on this machine -- run: claude auth login'
    dim "no \"$keychain\" item in the login keychain"
    dim 'a machine that authenticates another way sets auth_check = false'
  fi
fi
