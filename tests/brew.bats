#!/usr/bin/env bats
#
# lib/brew.sh. Nothing installs anything: brew_load and brew are stubbed.

setup() {
  load helper
  setup_sandbox
}

teardown() { teardown_sandbox; }

@test "bundle: a module with no Brewfile is success, not failure" {
  # A 1 here makes module_apply skip apply.sh with no error message.
  run brew_bundle "$DOT_TMP/nope/Brewfile" demo
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bundle: the missing-file check comes before the Homebrew check" {
  brew_load() { return 1; }

  run brew_bundle "$DOT_TMP/nope/Brewfile" demo
  [ "$status" -eq 0 ]
  [[ $output != *Homebrew* ]]
}

@test "bundle: a real Brewfile with no Homebrew fails and says which module" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 1; }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 1 ]
  [[ $output == *"Homebrew is not installed"* ]]
  [[ $output == *demo* ]]
}

@test "bundle: a dry run announces the file and installs nothing" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() { printf 'BREW-WAS-CALLED\n'; }
  export DOT_DRY_RUN=1

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 0 ]
  [[ $output != *BREW-WAS-CALLED* ]]
  [[ $output == *"brew bundle"* ]]
}

@test "bundle: the label defaults to the module directory name" {
  # $label must be a separate `local`: merged with $file, the default expands
  # before $file is assigned (SC2318) and the name is silently empty.
  mkdir -p "$DOT_TMP/modules/widgets"
  printf 'brew "jq"\n' >"$DOT_TMP/modules/widgets/Brewfile"
  brew_load() { return 1; }

  run brew_bundle "$DOT_TMP/modules/widgets/Brewfile"
  [ "$status" -eq 1 ]
  [[ $output == *widgets* ]]
}

@test "bundle: a failing brew bundle is reported against the module" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() { return 1; }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 1 ]
  [[ $output == *"brew bundle failed for demo"* ]]
}

@test "bundle: brew's own output is kept, indented and out of the way" {
  # It streams through a pipe now, so two things can go wrong at once: the
  # output can be swallowed, and the failure can be lost because the pipeline's
  # status is the last command's. Both are checked here.
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() {
    printf 'Using jq\na second line\n'
    return 1
  }
  brew_missing() { return 2; }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 1 ]
  [[ $output == *"Using jq"* ]]
  [[ $output == *"a second line"* ]]
  # Indented past this repo's own lines, so the eye can skip it.
  [[ $output =~ ^[[:space:]]{4,}Using\ jq ]] ||
    [[ $(grep 'Using jq' <<<"$output") =~ ^[[:space:]]{4,} ]]
}

@test "bundle: a package still missing after a failure is named" {
  # brew's own hundreds of lines are above by now, and "failed" alone is not
  # something anyone can act on.
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() { return 1; }
  brew_missing() {
    printf 'Formula jq\n'
    return 1
  }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 1 ]
  says 'still missing' 'Formula jq'
}

@test "bundle: --no-upgrade is passed, so apply never bumps a version" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() { printf '%s\n' "$*"; }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 0 ]
  [[ $output == *"--no-upgrade"* ]]
}

# --- brew_missing -----------------------------------------------------------
#
# The three states are the whole point of this function, and 2 is the one that
# matters: a check that could not run must never be read as "all installed", or
# brew_check reports green on a machine with nothing on it.

@test "missing: a module with no Brewfile is satisfied without asking brew" {
  brew() { printf 'BREW-WAS-CALLED\n'; }

  run brew_missing "$DOT_TMP/nope/Brewfile"
  [ "$status" -eq 0 ]
  [[ $output != *BREW-WAS-CALLED* ]]
}

@test "missing: no Homebrew is 2 -- could not run, not 'nothing missing'" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"

  # No brew function and none on PATH: `command -v brew` is the guard. Narrowed
  # inside a subshell, because an empty PATH leaking out takes `rm` from bats'
  # own teardown with it. Nothing on this branch runs an external command.
  local status=0
  (
    PATH=
    brew_missing "$DOT_TMP/Brewfile"
  ) || status=$?
  [ "$status" -eq 2 ]
}

@test "missing: everything installed is 0, and says nothing" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew() { return 0; }

  run brew_missing "$DOT_TMP/Brewfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing: every absent package is named, formula and cask alike" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  # brew's real wording, arrow included: the sed deliberately does not anchor
  # on that glyph, because a C locale would make an anchored match find
  # nothing and every package would silently read as installed.
  brew() {
    printf "brew bundle can't satisfy your Brewfile's dependencies.\n"
    printf '\xe2\x86\x92 Cask docker needs to be installed.\n'
    printf '\xe2\x86\x92 Formula jq needs to be installed.\n'
    printf 'Satisfy missing dependencies with `brew bundle install`.\n'
    return 1
  }

  run brew_missing "$DOT_TMP/Brewfile"
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "Cask docker" ]
  [ "${lines[1]}" = "Formula jq" ]
}

@test "missing: a failure it cannot parse is 2, never a silent 0" {
  # The hazard: brew fails for a reason that is not a missing package, the sed
  # matches nothing, and an empty list reads as "all installed" unless the
  # emptiness itself is turned back into 2.
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew() {
    printf 'Error: the Brewfile could not be read.\n'
    return 1
  }

  run brew_missing "$DOT_TMP/Brewfile"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "missing: the check never mutates the machine" {
  # Recorded to a file, not printed: on the satisfied path brew_missing
  # swallows brew's output, so stdout cannot answer what brew was asked.
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew() {
    printf 'auto-update=%s args=%s\n' \
      "${HOMEBREW_NO_AUTO_UPDATE:-unset}" "$*" >"$DOT_TMP/brew-call"
    return 0
  }

  run brew_missing "$DOT_TMP/Brewfile"
  [ "$status" -eq 0 ]

  local call
  call=$(cat "$DOT_TMP/brew-call")
  [[ $call == *"auto-update=1"* ]]
  [[ $call == *"bundle check"* ]]
  [[ $call == *"--no-upgrade"* ]]
}

# --- brew_bundle diagnostics ------------------------------------------------
#
# brew's own output is hundreds of lines above by the time the failure lands,
# so "failed" alone is not something a user can act on.

@test "bundle: a failed run names the packages that are still absent" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() { return 1; }
  brew_missing() {
    printf 'Formula jq\n'
    return 1
  }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 1 ]
  # `says`, not a literal: "still missing" is a label in the aligned column now,
  # and how wide that column is belongs to lib/ui.sh rather than to this test.
  says 'still missing' 'Formula jq'
}

@test "bundle: a missing cask points at the one flag that fixes it" {
  # A cask already in /Applications by hand is the common case, and --adopt is
  # not something anyone guesses.
  printf 'cask "docker"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() { return 1; }
  brew_missing() {
    printf 'Cask docker\n'
    return 1
  }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 1 ]
  [[ $output == *"--adopt"* ]]
}

@test "bundle: a formula-only failure does not offer the cask advice" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() { return 1; }
  brew_missing() {
    printf 'Formula jq\n'
    return 1
  }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [[ $output != *"--adopt"* ]]
}

@test "bundle: brew that cannot say what is missing says so, not nothing" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew() { return 1; }
  brew_missing() { return 2; }

  run brew_bundle "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 1 ]
  [[ $output == *"could not say what is missing"* ]]
}

# --- brew_check -------------------------------------------------------------
#
# doctor's read-only half. Without it a half-installed module reports green:
# doctor would be looking at nothing but symlinks.

@test "check: a module with no Brewfile is silent, and not a failure" {
  run brew_check "$DOT_TMP/nope/Brewfile" demo
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check: no Homebrew is a failure that names the module" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 1; }

  run brew_check "$DOT_TMP/Brewfile" demo
  [ "$status" -eq 1 ]
  [[ $output == *"Homebrew is not installed"* ]]
  [[ $output == *demo* ]]
}

@test "check: the label defaults to the module directory name" {
  mkdir -p "$DOT_TMP/modules/widgets"
  printf 'brew "jq"\n' >"$DOT_TMP/modules/widgets/Brewfile"
  brew_load() { return 1; }

  run brew_check "$DOT_TMP/modules/widgets/Brewfile"
  [[ $output == *widgets* ]]
}

@test "check: everything installed reports green and fails nothing" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew_missing() { return 0; }

  brew_check "$DOT_TMP/Brewfile" demo
  [ "$DOT_FAILURES" -eq 0 ]
  [ "$DOT_WARNINGS" -eq 0 ]
}

@test "check: each absent package is its own failure, with the fix" {
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew_missing() {
    printf 'Formula jq\nCask docker\n'
    return 1
  }

  run brew_check "$DOT_TMP/Brewfile" demo
  [[ $output == *"Formula jq is not installed"* ]]
  [[ $output == *"Cask docker is not installed"* ]]
  [[ $output == *"dot apply"* ]]

  # One failure per package, not one for the batch: the tally is the exit code.
  brew_check "$DOT_TMP/Brewfile" demo >/dev/null 2>&1
  [ "$DOT_FAILURES" -eq 2 ]
}

@test "check: a check that could not answer warns, and never passes" {
  # The 2 branch. Calling it green is the bug this whole three-state contract
  # exists to prevent; calling it a failure would make every machine without
  # Homebrew's cache red for a reason the user cannot fix.
  printf 'brew "jq"\n' >"$DOT_TMP/Brewfile"
  brew_load() { return 0; }
  brew_missing() { return 2; }

  run brew_check "$DOT_TMP/Brewfile" demo
  [[ $output == *"could not be checked"* ]]

  brew_check "$DOT_TMP/Brewfile" demo >/dev/null 2>&1
  [ "$DOT_FAILURES" -eq 0 ]
  [ "$DOT_WARNINGS" -eq 1 ]
}
