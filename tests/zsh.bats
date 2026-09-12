#!/usr/bin/env bats
#
# modules/zsh/doctor.sh, executed the way lib/modules.sh runs it.

load helper

setup() {
  setup_sandbox
  # Pinned: a real XDG_CONFIG_HOME would send DOT_CONFIG_HOME outside the sandbox.
  export XDG_CONFIG_HOME="$HOME/.config"
}
teardown() { teardown_sandbox; }

doctor() { run env -u ZDOTDIR "$BASH" "$DOT_ROOT/modules/zsh/doctor.sh"; }

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
  run env ZDOTDIR="$HOME/elsewhere" "$BASH" "$DOT_ROOT/modules/zsh/doctor.sh"
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"ZDOTDIR is $HOME/elsewhere"* ]]
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
