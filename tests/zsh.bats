#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
  export XDG_CONFIG_HOME="$HOME/.config"

  DSCL="$DOT_TMP/dscl"
  with_login_shell /bin/zsh
}
teardown() { teardown_sandbox; }

with_login_shell() {
  if [[ -z $1 ]]; then
    printf '#!/usr/bin/env bash\nexit 1\n' >"$DSCL"
  else
    printf '#!/usr/bin/env bash\nprintf "UserShell: %%s\\n" "%s"\n' "$1" >"$DSCL"
  fi
  chmod +x "$DSCL"
}

doctor() {
  run env -u ZDOTDIR DOT_DSCL_BIN="$DSCL" \
    "$BASH" "$DOT_ROOT/modules/zsh/doctor.sh"
}

@test "clean home passes" {
  doctor
  [ "$status" -eq 0 ]
  [[ $output == *"no dead config"* ]]
}

@test "a stray ~/.zshrc warns, and the warning reaches the driver" {
  printf 'eval "$(some-tool init zsh)"\n' >"$HOME/.zshrc"

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *".zshrc"* ]]
  [[ $output == *"local.zsh"* ]]
}

@test "every file zsh would read from ZDOTDIR is reported" {
  local f
  for f in .zshrc .zprofile .zlogin .zlogout; do
    printf 'x\n' >"$HOME/$f"
  done

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  for f in .zshrc .zprofile .zlogin .zlogout; do
    [[ $output == *"$f"* ]] || {
      echo "$f not reported"
      return 1
    }
  done
}

@test "~/.zshenv is not a stray -- it is the one file that belongs there" {
  printf 'export ZDOTDIR=...\n' >"$HOME/.zshenv"
  doctor
  [ "$status" -eq 0 ]
}

@test "a hijacked ZDOTDIR is reported" {
  run env ZDOTDIR="$HOME/elsewhere" DOT_DSCL_BIN="$DSCL" \
    "$BASH" "$DOT_ROOT/modules/zsh/doctor.sh"
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"ZDOTDIR is $HOME/elsewhere"* ]]
}

@test "a login shell that is not zsh makes the whole module dead" {
  with_login_shell /bin/bash

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"/bin/bash"* ]]
  [[ $output == *"chsh -s"* ]]
}

@test "the login shell is read from the account, not from \$SHELL" {
  with_login_shell /bin/bash

  run env -u ZDOTDIR SHELL=/bin/zsh DOT_DSCL_BIN="$DSCL" \
    "$BASH" "$DOT_ROOT/modules/zsh/doctor.sh"
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"/bin/bash"* ]]
}

@test "a homebrew zsh is still zsh" {
  with_login_shell /opt/homebrew/bin/zsh

  doctor
  [ "$status" -eq 0 ]
  [[ $output == *"/opt/homebrew/bin/zsh"* ]]
}

@test "a dscl that answers nothing is never read as healthy" {
  with_login_shell ''

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"could not be read"* ]]
}

@test "no dscl at all says so, rather than nothing" {
  run env -u ZDOTDIR DOT_DSCL_BIN="$DOT_TMP/not-there" \
    "$BASH" "$DOT_ROOT/modules/zsh/doctor.sh"
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"cannot be checked"* ]]
}

@test "the check writes nothing" {
  local before
  before=$(home_snapshot)
  doctor
  [ "$(home_snapshot)" = "$before" ]
}

@test "an unset ZDOTDIR is not an accusation" {
  doctor
  [[ $output != *"ZDOTDIR is "*", expected"* ]]
}

@test "syntax: every zsh file this module links parses" {
  command -v zsh >/dev/null || skip 'no zsh on this machine'

  local f checked=0
  while IFS= read -r f; do
    checked=$((checked + 1))
    run zsh -n "$f"
    [ "$status" -eq 0 ] || {
      echo "zsh -n rejected ${f#"$DOT_ROOT"/}:"
      echo "$output"
      return 1
    }
  done < <(find "$DOT_ROOT/modules/zsh/home" -type f)

  [ "$checked" -gt 0 ]
}

@test "apply: a ~/.config/op that others can open is set to 700" {
  mkdir -p "$HOME/.config/op"
  chmod 755 "$HOME/.config/op"

  run "$BASH" "$DOT_ROOT/modules/zsh/apply.sh"
  [ "$status" -eq 0 ]
  [[ $output == *"755 -> 700"* ]]
  [ "$(stat -f '%Lp' "$HOME/.config/op")" = 700 ]
}

@test "apply: a dry run names the chmod and does not make it" {
  mkdir -p "$HOME/.config/op"
  chmod 755 "$HOME/.config/op"

  run env DOT_DRY_RUN=1 "$BASH" "$DOT_ROOT/modules/zsh/apply.sh"
  [ "$status" -eq 0 ]
  [[ $output == *"755 -> 700"* ]]
  [ "$(stat -f '%Lp' "$HOME/.config/op")" = 755 ]
}

@test "apply: a ~/.config/op already at 700 is left alone, silently" {
  mkdir -p "$HOME/.config/op"
  chmod 700 "$HOME/.config/op"

  run "$BASH" "$DOT_ROOT/modules/zsh/apply.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "apply: no ~/.config/op is not created" {
  run "$BASH" "$DOT_ROOT/modules/zsh/apply.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/op" ]
}

@test "doctor: a ~/.config/op that op would refuse warns" {
  mkdir -p "$HOME/.config/op"
  chmod 755 "$HOME/.config/op"

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"op refuses it"* ]]
}

@test "doctor: a ~/.config/op at 700 passes" {
  mkdir -p "$HOME/.config/op"
  chmod 700 "$HOME/.config/op"

  doctor
  [ "$status" -eq 0 ]
  [[ $output == *"op will read it"* ]]
}
