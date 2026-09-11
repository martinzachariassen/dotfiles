#!/usr/bin/env bash
#
# Installers append to $HOME/.zshrc, which ZDOTDIR makes dead: no error, the
# tool is just absent from every shell. A real file, so neither fs_check_tree
# nor the orphan scan can see it.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

zdotdir="$DOT_CONFIG_HOME/zsh"

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
