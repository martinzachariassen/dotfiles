#!/usr/bin/env bats
#
# core/doctor.sh: the checks every machine gets, whatever its modules.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

# --- Command Line Tools -------------------------------------------------------
#
# install.sh step 1, and until now the only step nothing checked again. A
# hosted runner and a developer Mac both have working tools, so the branches
# that matter are only reachable through the input.
#
# with_xcode_select BODY -- an xcode-select whose `-p` behaves like BODY.
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
  # The failure this check exists for. `xcode-select -p` answers from a stored
  # preference rather than from the disk, so after an OS upgrade moves or drops
  # the directory it keeps printing the old path, exit 0 and all -- while every
  # git and cc fails with "invalid active developer path".
  config_generate "A" "a@b.c" ""
  pass_core_checks
  with_xcode_select "printf '%s\\n' '$DOT_TMP/gone'"

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"broken"* ]]
  [[ $output == *"$DOT_TMP/gone"* ]]
}

@test "doctor: a developer directory holding the tools passes" {
  # Present is not enough: the check is for the binaries under it, because an
  # empty directory at the right path is exactly what a half-removed CLT is.
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
