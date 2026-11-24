#!/usr/bin/env bats

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

with_xcode_select() {
  mkdir -p "$DOT_TMP/stub"
  printf '#!/usr/bin/env bash\n%s\n' "$1" >"$DOT_TMP/stub/xcode-select"
  chmod +x "$DOT_TMP/stub/xcode-select"
  export DOT_XCODE_SELECT="$DOT_TMP/stub/xcode-select"
}

@test "doctor: missing Command Line Tools fail, and name the installer" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  with_xcode_select 'exit 2'

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"xcode-select --install"* ]]
}

@test "doctor: a developer directory that is gone is not a healthy answer" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  with_xcode_select "printf '%s\\n' '$DOT_TMP/gone'"

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"broken"* ]]
  [[ $output == *"$DOT_TMP/gone"* ]]
}

@test "doctor: a developer directory holding the tools passes" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  mkdir -p "$DOT_TMP/clt/usr/bin"
  printf '#!/usr/bin/env bash\n' >"$DOT_TMP/clt/usr/bin/git"
  chmod +x "$DOT_TMP/clt/usr/bin/git"
  with_xcode_select "printf '%s\\n' '$DOT_TMP/clt'"

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 0 ]
  [[ $output == *"Everything looks right"* ]]
}

@test "doctor: a taplo that crashed is reported as a check that did not run" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  printf '#!/bin/sh\nexit 101\n' >"$DOT_TMP/taplo-crash"
  chmod +x "$DOT_TMP/taplo-crash"

  export DOT_TAPLO_BIN="$DOT_TMP/taplo-crash"

  run "$DOT_ROOT/bin/dot" doctor
  [[ $output == *"could not check it"* ]]
  [[ $output != *"not valid TOML"* ]]
}

@test "doctor: a shim that lost its executable bit is not called missing" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  chmod -x "$HOME/.local/bin/dot"

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"not executable"* ]]
  [[ $output != *"not installed"* ]]
}

@test "doctor: a shim that is genuinely absent is still called missing" {
  config_generate "A" "a@b.c" ""

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  says dot "not installed at ~/.local/bin/dot -- run: dot apply"
  [[ $output != *"not executable"* ]]
}

doctor_with_git() {
  with_git
  run env PATH="$DOT_TMP/stub:$PATH" "$DOT_ROOT/bin/dot" doctor --verbose "$@"
}

@test "doctor: a repo behind its upstream warns, and names the fix" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  GIT_COUNTS=$'0\t3' doctor_with_git

  says git "3 commits behind origin/main, as of the last fetch -- run: dot apply --pull"
  [[ $output == *"1 warning"* ]]
}

@test "doctor: a repo that diverged from its upstream warns" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  GIT_COUNTS=$'2\t1' doctor_with_git

  says git "diverged from origin/main, 2 ahead and 1 behind"
}

@test "doctor: a repo ahead of its upstream is only noted" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  GIT_COUNTS=$'1\t0' doctor_with_git

  [ "$status" -eq 0 ]
  says git "1 commit ahead of origin/main"
  [[ $output != *"warning"* ]]
}

@test "doctor: a repo level with its upstream passes, and says how fresh that is" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  doctor_with_git

  [ "$status" -eq 0 ]
  says git "level with origin/main, as of the last fetch"
}

@test "doctor: a branch without an upstream is not a failure" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  GIT_NO_UPSTREAM=1 doctor_with_git

  [ "$status" -eq 0 ]
  says git "no upstream branch"
}

@test "doctor: a comparison that could not run is a warning, never green" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  GIT_REVLIST_FAILS=1 doctor_with_git

  says git "could not compare with origin/main"
  [[ $output != *"level with"* ]]
}

@test "doctor: counts git did not print as numbers are not read as level" {
  config_generate "A" "a@b.c" ""
  pass_core_checks
  GIT_COUNTS='garbage' doctor_with_git

  says git "could not compare with origin/main"
  [[ $output != *"level with"* ]]
}
