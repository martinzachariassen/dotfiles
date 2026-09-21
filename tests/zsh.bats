#!/usr/bin/env bats
#
# modules/zsh/doctor.sh, executed the way lib/modules.sh runs it.

load helper

setup() {
  setup_sandbox
  # Pinned: a real XDG_CONFIG_HOME would send DOT_CONFIG_HOME outside the sandbox.
  export XDG_CONFIG_HOME="$HOME/.config"

  # The login shell is a property of the ACCOUNT, which no sandbox $HOME can
  # hold, so it is shadowed to a healthy answer and every test below says only
  # what it is about. A hosted runner's account is not on zsh, and without this
  # every test in this file would be about that instead.
  DSCL="$DOT_TMP/dscl"
  with_login_shell /bin/zsh
}
teardown() { teardown_sandbox; }

# with_login_shell PATH -- a dscl whose UserShell record reads PATH. An empty
# PATH is a dscl that answers nothing at all, which is its own branch.
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
  # Not 1: nothing is broken. Not 0: fold_status must see something was said.
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
  # If ZDOTDIR points elsewhere, $HOME/.zshrc is live and "delete it" is wrong.
  run env ZDOTDIR="$HOME/elsewhere" DOT_DSCL_BIN="$DSCL" \
    "$BASH" "$DOT_ROOT/modules/zsh/doctor.sh"
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"ZDOTDIR is $HOME/elsewhere"* ]]
}

# --- the shell that reads any of it ------------------------------------------
#
# Everything else in this file asks what zsh will read. None of it means
# anything if zsh is not the shell that starts, and nothing else in the repo
# would ever notice: the link is correct, the layout is correct, and not one
# line of it is sourced.

@test "a login shell that is not zsh makes the whole module dead" {
  # Migrated accounts keep the shell they were created with, and macOS only
  # defaults to zsh for accounts made since Catalina. The symptom is that
  # nothing happens -- every check here passes and no alias exists.
  with_login_shell /bin/bash

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"/bin/bash"* ]]
  [[ $output == *"chsh -s"* ]]
}

@test "the login shell is read from the account, not from \$SHELL" {
  # $SHELL is whatever the RUNNING shell was told, so a `zsh` typed into a bash
  # login window answers for the window and not for the account -- which is the
  # one case worth catching, answered wrongly. A doctor reading $SHELL would
  # pass this test's machine and fail the user's.
  with_login_shell /bin/bash

  run env -u ZDOTDIR SHELL=/bin/zsh DOT_DSCL_BIN="$DSCL" \
    "$BASH" "$DOT_ROOT/modules/zsh/doctor.sh"
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"/bin/bash"* ]]
}

@test "a homebrew zsh is still zsh" {
  # /opt/homebrew/bin/zsh is what `chsh` points at on a machine that wants a
  # current one. Matching the path exactly would nag it forever.
  with_login_shell /opt/homebrew/bin/zsh

  doctor
  [ "$status" -eq 0 ]
  [[ $output == *"/opt/homebrew/bin/zsh"* ]]
}

@test "a dscl that answers nothing is never read as healthy" {
  # The same three-state rule brew_missing keeps: a question that could not be
  # asked is not a green answer.
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
  # doctor run from bash, cron or CI cannot observe it.
  doctor
  [[ $output != *"ZDOTDIR is "*", expected"* ]]
}

# --- What the module actually ships ------------------------------------------

@test "syntax: every zsh file this module links parses" {
  # The only shipped files neither shellcheck nor shfmt sees. `zsh -n` parses
  # without executing: these files run `eval` and set PATH.
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

  # Or a rename makes this pass over nothing, forever.
  [ "$checked" -gt 0 ]
}
