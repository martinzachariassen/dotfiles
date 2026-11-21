#!/usr/bin/env bats

setup() {
  load helper
  setup_sandbox

  REPO="$DOT_TMP/repo"
  MODULE="$REPO/modules/demo"
  mkdir -p "$MODULE/home/.config/demo"
  printf 'description = "demo"\n' >"$MODULE/module.toml"
  printf 'content\n' >"$MODULE/home/.config/demo/kept.conf"
  DOT_ROOT="$REPO"
}

teardown() { teardown_sandbox; }

link_one() {
  modules_enabled_dirs() { printf '%s\n' "$MODULE"; }
  fs_link_tree "$MODULE"
}

@test "unlink: removes a symlink, and says so" {
  link_one
  run fs_unlink "$HOME/.config/demo/kept.conf"
  [ ! -e "$HOME/.config/demo/kept.conf" ]
  says unlink "~/.config/demo/kept.conf"
}

@test "unlink: leaves a real file alone, and does not claim otherwise" {
  mkdir -p "$HOME/.config/demo"
  printf 'mine\n' >"$HOME/.config/demo/kept.conf"
  run fs_unlink "$HOME/.config/demo/kept.conf"
  [ -f "$HOME/.config/demo/kept.conf" ]
  [ -z "$output" ]
}

@test "unlink: a dry run announces and changes nothing" {
  link_one
  DOT_DRY_RUN=1
  run fs_unlink "$HOME/.config/demo/kept.conf"
  [[ $output == *unlink* ]]
  [ -L "$HOME/.config/demo/kept.conf" ]
}

@test "discard: removes a generated file" {
  printf 'generated\n' >"$HOME/generated.conf"
  fs_discard "$HOME/generated.conf"
  [ ! -e "$HOME/generated.conf" ]
}

@test "discard: a missing file is success, not failure" {
  run fs_discard "$HOME/never-existed"
  [ "$status" -eq 0 ]
}

@test "discard: a dry run changes nothing" {
  printf 'generated\n' >"$HOME/generated.conf"
  DOT_DRY_RUN=1
  fs_discard "$HOME/generated.conf"
  [ -f "$HOME/generated.conf" ]
}

@test "repo links: finds a link into the repo" {
  link_one
  run fs_repo_links
  [[ $output == *kept.conf* ]]
}

@test "repo links: finds links from a DISABLED module too" {
  link_one
  modules_enabled_dirs() { :; }
  run fs_repo_links
  [[ $output == *kept.conf* ]]
}

@test "repo links: ignores a link pointing outside the repo" {
  link_one
  printf 'x\n' >"$DOT_TMP/elsewhere.txt"
  ln -s "$DOT_TMP/elsewhere.txt" "$HOME/.config/demo/foreign.conf"

  run fs_repo_links
  [[ $output != *foreign.conf* ]]
}

@test "repo links: ignores real files" {
  link_one
  printf 'x\n' >"$HOME/.config/demo/notes.txt"
  run fs_repo_links
  [[ $output != *notes.txt* ]]
}

@test "uninstall: --dry-run exits clean and changes nothing" {
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  fs_link_tree "$DOT_ROOT/modules/git"
  [ -L "$HOME/.config/git/config" ]

  local before after
  before=$(home_snapshot)

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Nothing was changed"* ]]
  [ -L "$HOME/.config/git/config" ]
  [ -e "$DOT_ROOT/.git" ]

  after=$(home_snapshot)
  [ "$before" = "$after" ] || {
    echo "the dry run wrote to \$HOME:"
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
    return 1
  }
}

@test "uninstall: applications are dealt with before Homebrew is" {
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]

  apps=$(printf '%s\n' "$output" | grep -n ' Applications ' | cut -d: -f1)
  brew=$(printf '%s\n' "$output" | grep -n ' Homebrew and the repo ' | cut -d: -f1)
  [ -n "$apps" ]
  [ -n "$brew" ]
  [ "$apps" -lt "$brew" ]
}

@test "uninstall: finds Homebrew even when the invoking shell cannot" {
  command -v brew >/dev/null 2>&1 || skip 'no Homebrew on this machine'
  local n_casks
  n_casks=$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')
  ((n_casks > 0)) || skip 'no casks installed, so nothing would be stranded'

  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  run env -u HOMEBREW_PREFIX PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    DOT_ROOT="$DOT_ROOT" HOME="$HOME" DOT_STATE="$DOT_STATE" \
    DOT_CONFIG="$DOT_CONFIG" "$BASH" "$DOT_ROOT/uninstall.sh" --dry-run

  [ "$status" -eq 0 ]

  local listed
  listed=$(printf '%s\n' "$output" | grep -c 'uninstall  ' || true)
  [ "$listed" -eq "$n_casks" ]

  [[ $output == *"formulae it manages"* ]]
}

@test "uninstall: refuses an unknown option" {
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry
  [ "$status" -ne 0 ]
  [[ $output == *"unknown option"* ]]
}

@test "uninstall: refuses to run unattended without --dry-run" {
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" </dev/null
  [ "$status" -ne 0 ]
  [[ $output == *"Refusing to run unattended"* ]]
}

@test "uninstall: a state directory holding foreign files is left alone" {
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$DOT_STATE"
  printf 'from an older tool\n' >"$DOT_STATE/brew-bundle.log"

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"left alone"* ]]
  ! says remove "~/.local/state"
  [ -f "$DOT_STATE/brew-bundle.log" ]
}

@test "uninstall: removing the state directory is announced in the preview" {
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$DOT_STATE/backups"

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  says remove "${DOT_STATE/#$HOME/\~}"
  [[ $output != *"left alone"* ]]
  [ -d "$DOT_STATE/backups" ]
}

@test "uninstall: transcripts are removed, and the state directory still goes" {
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$DOT_STATE/logs" "$DOT_STATE/backups"
  printf 'a past run\n' >"$DOT_STATE/logs/20240101-000000.log"

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  says remove "${DOT_STATE/#$HOME/\~}/logs/20240101-000000.log"
  [[ $output != *"left alone"* ]]
  says remove "${DOT_STATE/#$HOME/\~}"
  [ -f "$DOT_STATE/logs/20240101-000000.log" ]
}

@test "uninstall: no state directory at all says nothing beyond None to keep" {
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  [ ! -d "$DOT_STATE" ]

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  says backups 'none to keep'
  [[ $output != *"left alone"* ]]
  ! says remove "~/.local/state"
}

@test "uninstall: the backup tree survives a dry run and is reported" {
  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$DOT_STATE/backups/20240101-000000"
  printf 'precious\n' >"$DOT_STATE/backups/20240101-000000/.zshrc"

  run env DOT_ROOT="$DOT_ROOT" bash "$DOT_ROOT/uninstall.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"kept"* ]]
  [ -f "$DOT_STATE/backups/20240101-000000/.zshrc" ]
}
