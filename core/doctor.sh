#!/usr/bin/env bash
#
# Core health checks. Read-only. Only things that fail silently earn a check.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if brew_load; then
  ok homebrew "$(brew --prefix)"
else
  fail homebrew 'not found'
fi

# Missing and not-executable are distinct causes. uninstall.sh tests -f on
# purpose: a shim that lost the bit is still ours to remove.
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

# `apply` runs these checks from the bootstrap shell, which predates the zsh
# module and can never have the right PATH. Once ~/.zshenv is linked the
# mechanism is in place and the statement is about the next shell, not this one.
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
  # a subshell would drop it -- the third answer would then be silently lost on
  # every run. One taplo invocation either way.
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
  # A checker that fell over is not evidence about the file. Said out loud
  # rather than swallowed, because the two heuristics left behind miss a typo
  # in the last table.
  if cfg_unchecked; then
    warn config "${DOT_TAPLO_BIN:-taplo} could not check it -- only the fallback heuristics ran"
  fi
else
  fail config 'missing -- run: dot config --init'
fi

ok repo "${DOT_ROOT/#$HOME/\~}"

# `dim`, not `warn`: true on every machine the repo is edited on, and a
# permanently yellow summary is the same bug as a permanently green one.
if git -C "$DOT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if [[ -n $(git -C "$DOT_ROOT" status --porcelain) ]]; then
    dim git 'uncommitted changes in the repo'
  else
    ok git 'clean'
  fi
fi
