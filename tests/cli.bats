#!/usr/bin/env bats
#
# bin/dot: how it reads the command line, and the Result line of each verb.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

dot() { run "$DOT_ROOT/bin/dot" "$@"; }

# Make the core checks pass so a doctor test isolates one thing. The real
# generator, not a printf'd lookalike: a hand-written shim is a second
# definition of the format core/doctor.sh greps for.
pass_core_checks() {
  DOT_DRY_RUN=0 bash "$DOT_ROOT/core/apply.sh" >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
}

@test "cli: no arguments prints the usage" {
  dot
  [ "$status" -eq 0 ]
  [[ $output == *"usage: dot"* ]]
}

@test "cli: an unknown command exits 1 and shows the usage" {
  dot frobnicate
  [ "$status" -eq 1 ]
  [[ $output == *"unknown command frobnicate"* ]]
  [[ $output == *"usage: dot"* ]]
}

@test "apply: a mistyped --dry-run is refused, not ignored" {
  dot apply --dry
  [ "$status" -ne 0 ]
  [[ $output == *"unknown option '--dry'"* ]]
  # Stopped before phase 1.
  [[ $output != *"Core packages"* ]]
}

@test "apply: --dry-run is accepted and changes nothing" {
  config_generate "A" "a@b.c" ""

  dot apply --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Dry run: nothing was changed."* ]]
  [ ! -e "$HOME/.local/bin/dot" ]
}

@test "apply: says which config it read before it changes anything" {
  config_generate "A" "a@b.c" ""

  dot apply --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"$DOT_CONFIG"* ]]
  [[ $output == *"dry run -- nothing will be changed"* ]]
}

@test "apply: module headings say how many are left" {
  config_generate "A" "a@b.c" "git"

  dot apply --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Module: git  [1/1]"* ]]
  [[ $output == *"1 enabled: git"* ]]
}

@test "apply: a real run leaves a transcript and names it" {
  # brew is stubbed: this is about the transcript, not packages. ~/.local/bin
  # is on PATH because apply now ends by running the doctor checks, and
  # core/doctor.sh rightly fails a machine that cannot reach its own shim.
  config_generate "A" "a@b.c" ""
  mkdir -p "$DOT_TMP/stub"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$DOT_TMP/stub/brew"
  chmod +x "$DOT_TMP/stub/brew"

  run env PATH="$DOT_TMP/stub:$HOME/.local/bin:$PATH" "$DOT_ROOT/bin/dot" apply
  [ "$status" -eq 0 ]

  local log="$DOT_STATE/logs/$DOT_RUN_ID.log"
  [ -f "$log" ]
  [[ $(cat "$log") == *"Core packages"* ]]
  [[ $(cat "$log") == *"Summary"* ]]
  [[ $output == *"Full output:"* ]]
}

@test "apply: a dry run writes no log" {
  # The log is the one non-symlink file an apply writes.
  config_generate "A" "a@b.c" ""

  dot apply --dry-run
  [ "$status" -eq 0 ]
  [ ! -d "$DOT_STATE/logs" ]
}

@test "apply: keeps the twenty most recent logs" {
  config_generate "A" "a@b.c" ""
  mkdir -p "$DOT_TMP/stub" "$DOT_STATE/logs"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$DOT_TMP/stub/brew"
  chmod +x "$DOT_TMP/stub/brew"

  # Names below this run's id, so they sort as older however the clock reads.
  local i
  for i in $(seq -w 1 25); do
    printf 'old\n' >"$DOT_STATE/logs/00000000-0000$i.log"
  done

  run env PATH="$DOT_TMP/stub:$HOME/.local/bin:$PATH" "$DOT_ROOT/bin/dot" apply
  [ "$status" -eq 0 ]

  local kept
  kept=$(find "$DOT_STATE/logs" -name '*.log' | wc -l | tr -d ' ')
  [ "$kept" -eq 20 ]
  # This run's own log survives its own prune.
  [ -f "$DOT_STATE/logs/$DOT_RUN_ID.log" ]
}

@test "doctor: an unlinked module fails the whole run" {
  config_generate "A" "a@b.c" "git"
  pass_core_checks

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"not linked"* ]]
  [[ $output != *"Everything looks right"* ]]
}

@test "doctor: a warning is not drowned out by the summary" {
  config_generate "A" "a@b.c" ""
  pass_core_checks

  mkdir -p "$HOME/.config/git"
  ln -s "$DOT_ROOT/bin/dot" "$HOME/.config/git/leftover"

  run "$DOT_ROOT/bin/dot" doctor

  [[ $output == *"unclaimed"* ]]
  [[ $output != *"Everything looks right"* ]]
  [[ $output == *"warnings above"* ]]
  # Still 0: `dot doctor && ...` must keep working.
  [ "$status" -eq 0 ]
}

@test "doctor: a clean machine still says so" {
  # A summary that never says "fine" is as useless as one that always does.
  config_generate "A" "a@b.c" ""
  pass_core_checks

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 0 ]
  [[ $output == *"Everything looks right"* ]]
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
  [[ $output == *"not installed in ~/.local/bin"* ]]
  [[ $output != *"not executable"* ]]
}

@test "doctor: a stale module name is a failure, not a shrug" {
  # Reported, not fatal: doctor is read-only and must reach the checks below.
  config_generate "A" "a@b.c" "$(printf 'git\ntypoo\n')"
  pass_core_checks

  run "$DOT_ROOT/bin/dot" doctor

  [ "$status" -eq 1 ]
  [[ $output == *"unknown module 'typoo'"* ]]
  [[ $output != *"Everything looks right"* ]]
  [[ $output == *"Module: git"* ]]
}

@test "config: an unknown option is refused" {
  dot config --initt
  [ "$status" -ne 0 ]
  [[ $output == *"unknown option '--initt'"* ]]
}

@test "config: --init refuses to overwrite a config that already exists" {
  config_generate "A" "a@b.c" ""

  dot config --init
  [ "$status" -ne 0 ]
  [[ $output == *"already exists"* ]]
}

@test "config: with no config yet, points at --init instead of opening an editor" {
  EDITOR=false dot config
  [ "$status" -ne 0 ]
  [[ $output == *"dot config --init"* ]]
}

@test "config: opens \$EDITOR on the config file, and on nothing else" {
  config_generate "A" "a@b.c" ""
  printf '#!/usr/bin/env bash\nprintf "EDITED[%%s]\\n" "$@"\n' >"$DOT_TMP/fake-editor"
  chmod +x "$DOT_TMP/fake-editor"

  EDITOR="$DOT_TMP/fake-editor" dot config
  [ "$status" -eq 0 ]
  [ "$output" = "EDITED[$DOT_CONFIG]" ]
}

@test "apply: a dry run on a fresh machine does not run the wizard" {
  # The fzf stub is the tripwire: if the wizard is reached, it says so.
  mkdir -p "$DOT_TMP/stub"
  printf '#!/usr/bin/env bash\necho WIZARD-RAN\n' >"$DOT_TMP/stub/fzf"
  chmod +x "$DOT_TMP/stub/fzf"

  run env PATH="$DOT_TMP/stub:$PATH" "$DOT_ROOT/bin/dot" apply --dry-run

  [ "$status" -ne 0 ]
  [[ $output != *"WIZARD-RAN"* ]]
  [[ $output == *"dot config --init"* ]]
  # Phase 1 was skipped on purpose, so there is no brew output to point at.
  [[ $output != *"brew output above"* ]]
  [ ! -f "$DOT_CONFIG" ]
}

@test "doctor: with no config, says how to make one rather than crashing" {
  run "$DOT_ROOT/bin/dot" doctor
  [ "$status" -ne 0 ]
  [[ $output == *"dot config --init"* ]]
  [[ $output != *dasel* ]]
}

@test "apply: ends by running the doctor checks against what it produced" {
  # The whole point of the pass: "Done." must mean "I looked", not "nothing
  # threw while I worked".
  config_generate "A" "a@b.c" ""
  mkdir -p "$DOT_TMP/stub"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$DOT_TMP/stub/brew"
  chmod +x "$DOT_TMP/stub/brew"

  run env PATH="$DOT_TMP/stub:$HOME/.local/bin:$PATH" "$DOT_ROOT/bin/dot" apply
  [ "$status" -eq 0 ]
  [[ $output == *"Orphaned links"* ]]
  [[ $output == *"dot         installed"* ]]
}

@test "apply: a machine the checks reject does not report success" {
  # Same run, with the shim unreachable. The work all succeeded; the machine
  # is still wrong, and the exit status has to say so.
  config_generate "A" "a@b.c" ""
  mkdir -p "$DOT_TMP/stub"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$DOT_TMP/stub/brew"
  chmod +x "$DOT_TMP/stub/brew"

  run env PATH="$DOT_TMP/stub:$PATH" "$DOT_ROOT/bin/dot" apply
  [ "$status" -ne 0 ]
  [[ $output == *"Finished with problems"* ]]
}

@test "apply: a dry run does not run the checks" {
  # They would report the drift the run deliberately did not fix.
  config_generate "A" "a@b.c" ""

  dot apply --dry-run
  [ "$status" -eq 0 ]
  [[ $output != *"Orphaned links"* ]]
}
