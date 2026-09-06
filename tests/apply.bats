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

# no_jq -- a PATH with nothing on it at all. lib/dot.sh needs no external
# command once DOT_ROOT and DOT_RUN_ID are given, so this is the honest shape
# of a machine that never installed the module whose hook is running.
no_jq() {
  mkdir -p "$DOT_TMP/empty"
  run env -i PATH="$DOT_TMP/empty" HOME="$HOME" DOT_ROOT="$DOT_ROOT" \
    DOT_RUN_ID="$DOT_RUN_ID" DOT_DRY_RUN=0 DOT_MODULE=claude-code \
    DOT_MODULE_DIR="$DOT_ROOT/modules/claude-code" \
    "$BASH" "$DOT_ROOT/modules/claude-code/remove.sh"
}

@test "claude-code: remove.sh needs no jq when there is nothing of ours to remove" {
  # uninstall.sh runs EVERY module's remove.sh, enabled or not, and jq comes
  # from this module's own Brewfile. Deriving $want before the guards killed
  # the hook on its twelfth line, which failed the preview, which aborted the
  # whole uninstall -- on any machine that never enabled claude-code.
  [ ! -e "$HOME/.claude/settings.json" ]
  no_jq
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "claude-code: remove.sh without jq leaves settings.json alone and says why" {
  # A warning, not a failure: uninstall.sh stops before Homebrew on a failure,
  # and a few keys left in a file the user still owns is no reason for that.
  mkdir -p "$HOME/.claude"
  printf '{"model":"mine"}\n' >"$HOME/.claude/settings.json"

  no_jq
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"jq is not installed"* ]]
  [ "$(cat "$HOME/.claude/settings.json")" = '{"model":"mine"}' ]
}

@test "claude-code: settings.json that is valid JSON but not an object" {
  # `jq -e .` accepted [], and every jq program after that guard died on it.
  # `jq ... && mv` hid the death completely: set -e ignores a non-final member
  # of an && list, so both hooks printed their success line, exited 0, and left
  # a half-written temp file next to the file they had not touched.
  mkdir -p "$HOME/.claude"
  printf '[]\n' >"$HOME/.claude/settings.json"

  run_hook "$DOT_ROOT/modules/claude-code" apply.sh
  [ "$status" -ne 0 ]
  [[ $output == *"found array"* ]]
  [ "$(cat "$HOME/.claude/settings.json")" = "[]" ]

  run_hook "$DOT_ROOT/modules/claude-code" remove.sh
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [ "$(cat "$HOME/.claude/settings.json")" = "[]" ]

  # The temp file is the tell: a hook that gave up must leave no litter behind.
  [ "$(ls -A "$HOME/.claude")" = "settings.json" ]
}

@test "claude-code: the mode of the user's settings.json survives both hooks" {
  # mktemp is 0600 and `mv` carries that onto the destination, so a file the
  # user kept group- or world-readable came back private -- once per apply,
  # silently, to a file this module only ever claimed to merge into.
  mkdir -p "$HOME/.claude"
  printf '{"theirs":1}\n' >"$HOME/.claude/settings.json"
  chmod 644 "$HOME/.claude/settings.json"

  run_hook "$DOT_ROOT/modules/claude-code" apply.sh
  [ "$status" -eq 0 ]
  [ "$(stat -f '%Lp' "$HOME/.claude/settings.json")" = 644 ]

  run_hook "$DOT_ROOT/modules/claude-code" remove.sh
  [ "$status" -eq 0 ]
  [ "$(stat -f '%Lp' "$HOME/.claude/settings.json")" = 644 ]
}

@test "claude-code: valid JSON of the wrong shape is never called invalid" {
  # `jq -e .` exits non-zero on `null` and `false`, so all three hooks called
  # them invalid JSON -- a diagnosis that sends the user hunting for a syntax
  # error in a file whose syntax is fine. apply and remove name the type they
  # found; doctor, whose whole advice is "run dot apply", only has to stop
  # saying the wrong thing.
  mkdir -p "$HOME/.claude"
  local pair shape kind hook
  for pair in 'null:null' 'false:boolean' '42:number'; do
    shape=${pair%:*} kind=${pair#*:}
    printf '%s\n' "$shape" >"$HOME/.claude/settings.json"

    for hook in apply.sh remove.sh; do
      run_hook "$DOT_ROOT/modules/claude-code" "$hook"
      [ "$status" -ne 0 ]
      [[ $output == *"$kind"* ]] || {
        echo "$hook never said it found a $kind in a settings.json of \`$shape\`:"
        echo "$output"
        return 1
      }
    done

    run_hook "$DOT_ROOT/modules/claude-code" doctor.sh
    [ "$status" -ne 0 ]
    [[ $output != *"valid JSON"* ]]
  done
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
  [[ $output == *"unparseable text"* ]]
  # The user's file is theirs; a hook that cannot parse it may not replace it.
  [ "$(cat "$HOME/.claude/settings.json")" = "this is not json" ]
}
