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
    fail git "${dest/#$HOME/\~} is missing -- run: dot apply"
  else
    warn git 'no identity in config.toml, so no config.local was written'
  fi
  exit 0
fi

if [[ -n $signingkey ]]; then
  # `warn`, not `fail`: on a fresh machine 1Password is a cask that installs in
  # the same run, and enabling its agent is a manual step the user still owes.
  if grep -q '^\[commit\]' "$dest"; then
    ok git 'commit signing configured'
  else
    warn git 'signingkey is set but signing is off -- 1Password was not installed when this was written'
    dim 'install it, then re-run: dot apply'
  fi
fi

# git parses this file on every command; a malformed line makes all of them
# fail with an error naming a line number and nothing else.
if ! git config --file "$dest" --list >/dev/null 2>&1; then
  fail git "${dest/#$HOME/\~} does not parse -- delete it and run: dot apply"
fi

# Verification fails the way a missing file usually does not: git answers "No
# signature" for a commit that carries one, so the only symptom is a repo that
# looks unsigned. Asking git for the path rather than assuming it means a
# hand-edited config.local is checked as it actually reads.
allow=$(git config --file "$dest" --get gpg.ssh.allowedSignersFile 2>/dev/null || true)
if [[ -n $signingkey ]] && grep -q '^\[commit\]' "$dest"; then
  if [[ -z $allow ]]; then
    # The same shape test apply.sh makes, held against it by tests/git.bats.
    # A signingkey holding a PATH is a machine `dot apply` deliberately will
    # not fix, so sending it there is a yellow line that stays yellow with a
    # command that changes nothing. Name the cause apply names instead.
    if [[ $signingkey == ssh-*' '* || $signingkey == sk-*' '* ]]; then
      warn git 'signing is on but nothing verifies it -- run: dot apply'
      dim 'git log --show-signature answers "No signature" for your own commits'
    else
      warn git 'signature verification off -- signingkey is not a literal public key'
      dim 'put the key itself in config.toml, not a path to it'
    fi
  elif [[ ! -f $allow ]]; then
    fail git "allowedSignersFile points at a missing file: ${allow/#$HOME/\~}"
  elif ! grep -qF -- "$signingkey" "$allow"; then
    warn git "${allow/#$HOME/\~} does not hold the key in config.toml -- run: dot apply"
  else
    ok git 'signatures can be verified'
  fi
fi
