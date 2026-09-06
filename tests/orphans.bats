#!/usr/bin/env bats
#
# fs_orphans: what counts as an orphan, and what does not.

setup() {
  load helper
  setup_sandbox

  # A repo root inside the sandbox, so "points into the repo" is controllable.
  # The manifest makes the module visible to the registry, which is where the
  # scan roots come from.
  REPO="$DOT_TMP/repo"
  MODULE="$REPO/modules/demo"
  mkdir -p "$MODULE/home/.config/demo"
  printf 'description = "demo"\n' >"$MODULE/module.toml"
  DOT_ROOT="$REPO"
}

teardown() { teardown_sandbox; }

# Everything below claims exactly one file: ~/.config/demo/kept.conf
claim_one() {
  printf 'content\n' >"$MODULE/home/.config/demo/kept.conf"
  modules_enabled_dirs() { printf '%s\n' "$MODULE"; }
  fs_link_tree "$MODULE"
}

@test "orphans: a clean tree reports nothing" {
  claim_one
  run fs_orphans
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "orphans: a link into the repo that no module claims is reported" {
  claim_one
  ln -s "$MODULE/home/.config/demo/deleted.conf" "$HOME/.config/demo/stale.conf"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *stale.conf* ]]
  [[ $output != *kept.conf* ]]
}

@test "orphans: a link pointing outside the repo is left alone" {
  claim_one
  printf 'x\n' >"$DOT_TMP/elsewhere.txt"
  ln -s "$DOT_TMP/elsewhere.txt" "$HOME/.config/demo/foreign.conf"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output != *foreign.conf* ]]
}

@test "orphans: a real file is not a link and is never reported" {
  claim_one
  printf 'x\n' >"$HOME/.config/demo/notes.txt"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output != *notes.txt* ]]
}

@test "orphans: nothing enabled is not an error" {
  # claim_one first: without it the directory does not exist and an empty
  # output proves nothing.
  claim_one
  modules_enabled_dirs() { :; }

  run fs_orphans
  [ "$status" -eq 0 ]
  # An empty claimed map must not trip bash's unset-associative-array errors.
  [[ $output != *"invalid option"* ]]
  [[ $output != *"unbound variable"* ]]
  [[ $output == *kept.conf* ]]
}

@test "orphans: a link left behind by a DISABLED module is reported" {
  # The case this function exists for: scan roots must come from ALL modules.
  claim_one
  modules_enabled_dirs() { :; } # the module is now disabled in the config

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *kept.conf* ]]
}

@test "orphans: the two halves are separate -- wide scan, narrow claim" {
  # Two modules, one directory, one enabled: the only arrangement where a single
  # scan has to apply both rules at once.
  claim_one

  local other="$REPO/modules/other"
  mkdir -p "$other/home/.config/demo"
  printf 'description = "other"\n' >"$other/module.toml"
  printf 'content\n' >"$other/home/.config/demo/live.conf"
  fs_link_tree "$other"

  modules_enabled_dirs() { printf '%s\n' "$other"; }

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *kept.conf* ]]
  [[ $output != *live.conf* ]]
}

@test "orphans: deleting a file from the repo orphans its link" {
  # A sibling keeps the directory declared, so the scan still looks there.
  claim_one
  printf 'x\n' >"$MODULE/home/.config/demo/going.conf"
  fs_link_tree "$MODULE"
  rm "$MODULE/home/.config/demo/going.conf"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *going.conf* ]]
}

@test "orphans: emptying a directory does not hide the link it held" {
  # Renaming a skill, or dropping a module's only file in some directory, takes
  # that directory out of the declared set. The scan roots include the ancestors
  # too, and reach one level past each, so ~/.config -- still declared by a
  # sibling -- is what finds this.
  claim_one
  mkdir -p "$MODULE/home/.config/solo"
  printf 'x\n' >"$MODULE/home/.config/solo/only.conf"
  fs_link_tree "$MODULE"
  [ -L "$HOME/.config/solo/only.conf" ]

  rm -r "${MODULE:?}/home/.config/solo"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *only.conf* ]]
}

@test "orphans: every link is reported once, however many roots reach it" {
  # The ancestor roots overlap: ~/.config/demo is scanned in its own right and
  # again as a child of ~/.config. An uninstall that saw kept.conf twice would
  # print "unlink" twice for one file.
  claim_one
  modules_enabled_dirs() { :; }

  run fs_orphans
  [ "$status" -eq 0 ]
  [ "$(grep -c 'kept.conf' <<<"$output")" -eq 1 ]
}

@test "orphans: the boundary of the derived approach, pinned on purpose" {
  # Two levels below the nearest surviving root, and a top-level directory the
  # repo names nowhere any more. Both need a walk of all of $HOME, which stays
  # rejected on cost. If that trade is revisited, this test should fail loudly.
  claim_one
  mkdir -p "$MODULE/home/.config/a/b" "$MODULE/home/.gone"
  printf 'x\n' >"$MODULE/home/.config/a/b/deep.conf"
  printf 'x\n' >"$MODULE/home/.gone/lost.conf"
  fs_link_tree "$MODULE"

  rm -r "${MODULE:?}/home/.config/a" "${MODULE:?}/home/.gone"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output != *deep.conf* ]]
  [[ $output != *lost.conf* ]]
}
