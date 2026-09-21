#!/usr/bin/env bash
#
# Installers append to $HOME/.zshrc, which ZDOTDIR makes dead: no error, the
# tool is just absent from every shell. A real file, so neither fs_check_tree
# nor the orphan scan can see it.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

zdotdir="$DOT_CONFIG_HOME/zsh"

# Everything below asks what zsh will read, and none of it means anything if
# zsh is not the shell that starts.
#
# `dscl`, not $SHELL: $SHELL is whatever the RUNNING shell was told, so a `zsh`
# typed into a bash login window answers for the window rather than for the
# account -- the one case worth catching, answered wrongly. An input, because
# the branch that matters is the one a Mac set up since Catalina never takes.
dscl_bin=${DOT_DSCL_BIN:-/usr/bin/dscl}
if [[ -x $dscl_bin ]]; then
  # `if`, not a pipeline into sed: under pipefail a dscl that fails takes the
  # whole assignment down, and the ERR trap turns "could not be read" into a
  # crash. Never `|| true` -- that loses the distinction being tested.
  if record=$("$dscl_bin" . -read "/Users/$(id -un)" UserShell 2>/dev/null); then
    login_shell=$(sed -n 's/^UserShell: //p' <<<"$record")
  else
    login_shell=''
  fi

  case $login_shell in
    '') warn zsh "login shell could not be read -- ${dscl_bin} did not answer" ;;
    */zsh) ok zsh "login shell is $login_shell" ;;
    *)
      warn zsh "login shell is $login_shell, so none of this module is read"
      dim "change it: chsh -s $(command -v zsh 2>/dev/null || echo /bin/zsh)"
      ;;
  esac
else
  # A question that could not be asked is not a healthy answer.
  warn zsh "login shell cannot be checked -- $dscl_bin is not there"
fi

# Empty ZDOTDIR means "not observable from here", not "unset".
if [[ -n ${ZDOTDIR:-} && $ZDOTDIR != "$zdotdir" ]]; then
  warn zsh "ZDOTDIR is $ZDOTDIR, expected ${zdotdir/#$HOME/\~}"
fi

stray=()
for f in .zshrc .zprofile .zlogin .zlogout; do
  if [[ -e $HOME/$f ]]; then stray+=("$f"); fi
done

if ((${#stray[@]} > 0)); then
  warn zsh "dead config at ~/${stray[0]} -- zsh reads ${zdotdir/#$HOME/\~}, so it has no effect"
  for f in "${stray[@]:1}"; do
    warn zsh "dead config at ~/$f likewise"
  done
  dim "move the lines you want into ${zdotdir/#$HOME/\~}/local.zsh, then delete the file"
else
  ok zsh "no dead config in ~ (ZDOTDIR is ${zdotdir/#$HOME/\~})"
fi
