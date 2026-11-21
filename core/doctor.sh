#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# `xcode-select -p` alone answers from a stored preference, so it keeps printing
# the old path after a macOS upgrade has removed the directory.
xcode_select=${DOT_XCODE_SELECT:-/usr/bin/xcode-select}
if ! clt=$("$xcode_select" -p 2>/dev/null) || [[ -z $clt ]]; then
  fail xcode 'Command Line Tools missing -- run: xcode-select --install'
elif [[ ! -x $clt/usr/bin/git ]]; then
  fail xcode "developer directory is broken: $clt -- run: xcode-select --install"
else
  ok xcode "${clt/#$HOME/\~}"
fi

if brew_load; then
  ok homebrew "$(brew --prefix)"
else
  fail homebrew 'not found'
fi

shim="$HOME/.local/bin/dot"
short=${shim/#$HOME/\~}
if [[ ! -f $shim ]]; then
  fail dot "not installed at $short -- run: dot apply"
elif [[ ! -x $shim ]]; then
  fail dot "not executable: $short -- run: dot apply"
elif grep -qF "DOT_ROOT=\"$DOT_ROOT\"" "$shim" 2>/dev/null; then
  ok dot 'installed'
else
  fail dot "points at a different checkout: $short"
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ok PATH 'includes ~/.local/bin' ;;
  *)
    if [[ -L $HOME/.zshenv ]]; then
      dim PATH 'arrives with your next shell (~/.local/bin)'
    else
      fail PATH 'missing ~/.local/bin -- enable the zsh module, or add it'
    fi
    ;;
esac

if cfg_exists; then
  # Through a file, not `$(...)`: cfg_parse_problems sets DOT_CFG_UNCHECKED, and
  # a subshell would drop it.
  problems=$(mktemp "${TMPDIR:-/tmp}/dot-cfg.XXXXXX")
  cfg_parse_problems >"$problems"

  if [[ ! -s $problems ]]; then
    ok config "${DOT_CONFIG/#$HOME/\~}"
  else
    while IFS= read -r problem; do
      fail config "$problem"
    done <"$problems"
  fi
  rm -f "$problems"
  if cfg_unchecked; then
    warn config "${DOT_TAPLO_BIN:-taplo} could not check it -- only the fallback heuristics ran"
  fi
else
  fail config 'missing -- run: dot config --init'
fi

ok repo "${DOT_ROOT/#$HOME/\~}"

if git -C "$DOT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if [[ -n $(git -C "$DOT_ROOT" status --porcelain) ]]; then
    dim git 'uncommitted changes in the repo'
  else
    ok git 'clean'
  fi
fi
