#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

zdotdir="$DOT_CONFIG_HOME/zsh"

# dscl, not $SHELL: $SHELL describes the running shell, not the account.
dscl_bin=${DOT_DSCL_BIN:-/usr/bin/dscl}
if [[ -x $dscl_bin ]]; then
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
  warn zsh "login shell cannot be checked -- $dscl_bin is not there"
fi

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

op_dir="$HOME/.config/op"
if [[ -d $op_dir ]]; then
  op_mode=$(stat -f '%Lp' "$op_dir")
  if [[ $op_mode == 700 ]]; then
    ok op "${op_dir/#$HOME/\~} is 700, so op will read it"
  else
    warn op "${op_dir/#$HOME/\~} is $op_mode -- op refuses it, so every op:// reference fails"
    dim "fix: dot apply"
  fi
fi
