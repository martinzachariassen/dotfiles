#!/usr/bin/env bash
#
# config.local is generated, so fs_check_tree cannot see it, and apply.sh
# degrades silently by design: with a signingkey set but 1Password not installed
# yet it writes no signing block and warns once. That warning scrolls past, and
# every commit is then unsigned with nothing to notice.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

dest="$HOME/.config/git/config.local"
signingkey=$(module_setting git signingkey '')

if [[ ! -f $dest ]]; then
  # A run with an empty user.name/email writes no file at all, on purpose.
  if [[ -n $(cfg_get 'user.name') && -n $(cfg_get 'user.email') ]]; then
    fail 'git          ~/.config/git/config.local is missing -- run: dot apply'
  else
    warn 'git          no identity in config.toml, so no config.local was written'
  fi
  exit 0
fi

if [[ -n $signingkey ]]; then
  # `warn`, not `fail`: on a fresh machine 1Password is a cask that installs in
  # the same run, and enabling its agent is a manual step the user still owes.
  if grep -q '^\[commit\]' "$dest"; then
    ok 'git          commit signing configured'
  else
    warn 'git          signingkey is set but signing is off -- 1Password was not installed when this was written'
    dim '             install it, then re-run: dot apply'
  fi
fi

# git parses this file on every command; a malformed line makes all of them
# fail with an error naming a line number and nothing else.
if ! git config --file "$dest" --list >/dev/null 2>&1; then
  fail 'git          ~/.config/git/config.local does not parse -- delete it and run: dot apply'
fi
