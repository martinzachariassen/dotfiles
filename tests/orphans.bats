#!/usr/bin/env bats

setup() {
  load helper
  setup_sandbox

  REPO="$DOT_TMP/repo"
  MODULE="$REPO/modules/demo"
  mkdir -p "$MODULE/home/.config/demo"
  printf 'description = "demo"\n' >"$MODULE/module.toml"
  DOT_ROOT="$REPO"
}

teardown() { teardown_sandbox; }

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
  claim_one
  modules_enabled_dirs() { :; }

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output != *"invalid option"* ]]
  [[ $output != *"unbound variable"* ]]
  [[ $output == *kept.conf* ]]
}

@test "orphans: a link left behind by a DISABLED module is reported" {
  claim_one
  modules_enabled_dirs() { :; }

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *kept.conf* ]]
}

@test "orphans: the two halves are separate -- wide scan, narrow claim" {
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
  claim_one
  printf 'x\n' >"$MODULE/home/.config/demo/going.conf"
  fs_link_tree "$MODULE"
  rm "$MODULE/home/.config/demo/going.conf"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *going.conf* ]]
}

@test "orphans: emptying a directory does not hide the link it held" {
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
  claim_one
  modules_enabled_dirs() { :; }

  run fs_orphans
  [ "$status" -eq 0 ]
  [ "$(grep -c 'kept.conf' <<<"$output")" -eq 1 ]
}

@test "orphans: the boundary of the derived approach, pinned on purpose" {
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

@test "orphans: the module that ships an orphan is named alongside it" {
  claim_one
  modules_enabled_dirs() { :; }

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *"kept.conf"$'\t'"demo" ]]
}

@test "orphans: a path no module ships any more is named with no module" {
  claim_one
  printf 'x\n' >"$MODULE/home/.config/demo/going.conf"
  fs_link_tree "$MODULE"
  rm "$MODULE/home/.config/demo/going.conf"

  run fs_orphans
  [ "$status" -eq 0 ]
  [[ $output == *"going.conf"$'\t' ]]
}

@test "orphans: the empty module field is trailing, so read gets the path" {
  claim_one
  printf 'x\n' >"$MODULE/home/.config/demo/going.conf"
  fs_link_tree "$MODULE"
  rm "$MODULE/home/.config/demo/going.conf"

  local path mod
  IFS=$'\t' read -r path mod < <(fs_orphans)
  [[ $path == *going.conf ]]
  [ -z "$mod" ]
}
