#!/usr/bin/env bash
#
# Drift here is invisible -- a broken statusLine renders nothing, a changed
# theme says nothing at all -- so every managed leaf is compared, not sampled.
# Fair only because apply.sh manages no key Claude Code writes back.
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
  # Leaves, not top-level keys: .permissions.defaultMode is ours, .permissions
  # as a whole is not. Must match remove.sh (tests/contract.bats).
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

# --- sign-in ----------------------------------------------------------------
#
# Every key above is merged whether or not Claude Code can reach Anthropic, so
# a machine this module reports as perfect is still one run away from a login
# prompt. Nothing under ~/.claude answers it: the token is a login keychain
# item, which is also why no file check could have caught this.
#
# Attributes only, never `-w`. Reading the secret is what raises a keychain
# authorisation dialog, and a read-only check may not block on a human. The
# service name is the fragile half -- Anthropic owns it -- so it is named in
# the warning rather than only in this comment.
keychain=${DOT_CLAUDE_KEYCHAIN:-Claude Code-credentials}

if [[ -n ${ANTHROPIC_API_KEY:-} ]]; then
  ok auth 'ANTHROPIC_API_KEY is set'
elif security find-generic-password -s "$keychain" >/dev/null 2>&1; then
  ok auth 'signed in'
else
  warn auth 'never signed in on this machine -- run: claude auth login'
  dim "no \"$keychain\" item in the login keychain"
fi
