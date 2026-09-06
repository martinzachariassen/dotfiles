#!/usr/bin/env bats
#
# Idempotence. The property the whole design rests on -- "derive, never record"
# only works if deriving twice lands in the same place -- and the one thing
# nothing asserted. A second apply that relinks, rewrites or reports drift is a
# machine whose state nobody can reason about.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

run_hook() {
  local dir=$1 hook=$2
  run env DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN=0 \
    DOT_RUN_ID="$DOT_RUN_ID" DOT_MODULE="$(basename "$dir")" DOT_MODULE_DIR="$dir" \
    bash "$dir/$hook"
}

@test "linking twice: the second pass changes nothing" {
  local dir
  dir=$(fixture_module one)
  fixture_file "$dir" '.config/a/one.conf'
  fixture_file "$dir" '.config/b/two.conf'

  fs_link_tree "$dir"
  [ "$DOT_N_LINKED" -eq 2 ]

  local snapshot
  snapshot=$(home_snapshot)
  DOT_N_LINKED=0 DOT_N_RELINKED=0 DOT_N_BACKED_UP=0 DOT_N_UNCHANGED=0

  fs_link_tree "$dir"
  [ "$DOT_N_LINKED" -eq 0 ]
  [ "$DOT_N_RELINKED" -eq 0 ]
  [ "$DOT_N_BACKED_UP" -eq 0 ]
  [ "$DOT_N_UNCHANGED" -eq 2 ]
  [ "$snapshot" = "$(home_snapshot)" ]
}

@test "linking twice: no backup tree is created on the second pass" {
  local dir
  dir=$(fixture_module one)
  fixture_file "$dir" '.config/a/one.conf'

  fs_link_tree "$dir"
  ! fs_backup_used

  DOT_RUN_ID="${DOT_RUN_ID}-again"
  fs_link_tree "$dir"
  ! fs_backup_used
}

@test "after linking, the tree reports no drift and claims its own links" {
  local dir
  dir=$(fixture_module one)
  fixture_file "$dir" '.config/a/one.conf'

  fs_link_tree "$dir"
  run fs_check_tree "$dir"
  [ "$status" -eq 0 ]
  [ "$DOT_WARNINGS" -eq 0 ]
}

@test "git apply.sh writes a byte-identical file on a second run" {
  config_generate 'Ada Lovelace' 'ada@example.com' 'git' >/dev/null

  run_hook "$DOT_ROOT/modules/git" apply.sh
  [ "$status" -eq 0 ]
  local first
  first=$(cat "$HOME/.config/git/config.local")

  run_hook "$DOT_ROOT/modules/git" apply.sh
  [ "$status" -eq 0 ]
  [ "$first" = "$(cat "$HOME/.config/git/config.local")" ]
}

@test "claude-code apply.sh is a no-op on a second run" {
  mkdir -p "$HOME/.claude"
  printf '{}\n' >"$HOME/.claude/settings.json"

  run_hook "$DOT_ROOT/modules/claude-code" apply.sh
  [ "$status" -eq 0 ]
  local first
  first=$(cat "$HOME/.claude/settings.json")

  run_hook "$DOT_ROOT/modules/claude-code" apply.sh
  [ "$status" -eq 0 ]
  [ "$first" = "$(cat "$HOME/.claude/settings.json")" ]
}

@test "claude-code: apply, then doctor, then remove returns the file it found" {
  # The round trip is the promise: nothing this module did to a user's file
  # survives an uninstall, and nothing the user had is lost to an apply.
  mkdir -p "$HOME/.claude"
  printf '%s\n' '{"permissions":{"allow":["Bash(ls*)"]},"theirs":42}' \
    >"$HOME/.claude/settings.json"
  local before
  before=$(jq -S . "$HOME/.claude/settings.json")

  run_hook "$DOT_ROOT/modules/claude-code" apply.sh
  [ "$status" -eq 0 ]

  run_hook "$DOT_ROOT/modules/claude-code" doctor.sh
  [ "$status" -eq 0 ]

  run_hook "$DOT_ROOT/modules/claude-code" remove.sh
  [ "$status" -eq 0 ]
  [ "$before" = "$(jq -S . "$HOME/.claude/settings.json")" ]
}

@test "claude-code doctor reports a managed key the user changed" {
  mkdir -p "$HOME/.claude"
  printf '{}\n' >"$HOME/.claude/settings.json"
  run_hook "$DOT_ROOT/modules/claude-code" apply.sh

  local tmp="$HOME/.claude/x"
  jq '.model = "something-else"' "$HOME/.claude/settings.json" >"$tmp"
  mv "$tmp" "$HOME/.claude/settings.json"

  run_hook "$DOT_ROOT/modules/claude-code" doctor.sh
  [ "$status" -ne 0 ]
  [[ $output == *".model differs"* ]]
}

@test "claude-code apply refuses a settings.json that is not JSON" {
  mkdir -p "$HOME/.claude"
  printf 'this is not json\n' >"$HOME/.claude/settings.json"

  run_hook "$DOT_ROOT/modules/claude-code" apply.sh
  [ "$status" -ne 0 ]
  [[ $output == *"not valid JSON"* ]]
  # The user's file is theirs; a hook that cannot parse it may not replace it.
  [ "$(cat "$HOME/.claude/settings.json")" = "this is not json" ]
}
