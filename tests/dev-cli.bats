#!/usr/bin/env bats
#
# modules/dev-cli/remove.sh. apply.sh downloads runtimes and four go binaries
# into trees full of other projects' content, so nothing here is deletable --
# the warning IS the deliverable, the same trade macos-defaults makes.

load helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

remove() {
  run env DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    XDG_DATA_HOME="$HOME/.local/share" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN="${1:-0}" \
    DOT_MODULE=dev-cli DOT_MODULE_DIR="$DOT_ROOT/modules/dev-cli" \
    "$BASH" "$DOT_ROOT/modules/dev-cli/remove.sh"
}

@test "remove: says nothing on a machine that never enabled the module" {
  # uninstall.sh runs every module's remove.sh. A hook that warns about a
  # directory nobody has is noise in the one output an uninstall leaves.
  remove
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remove: names the mise tree, and refuses to delete it" {
  mkdir -p "$HOME/.local/share/mise/installs/go/1.0.0/bin"
  printf 'a real binary\n' >"$HOME/.local/share/mise/installs/go/1.0.0/bin/gopls"

  remove
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *".local/share/mise"* ]]
  [ -f "$HOME/.local/share/mise/installs/go/1.0.0/bin/gopls" ]
}

@test "remove: names Go's module cache separately from the mise tree" {
  # Two directories, two owners: ~/go predates this repo on most machines and
  # `go clean -modcache` is a different instruction from `mise implode`.
  mkdir -p "$HOME/go/pkg/mod"
  remove
  [[ $output == *"go/pkg/mod"* ]]
  [[ $output == *"go clean -modcache"* ]]
  [[ $output != *"mise implode"* ]]
}

@test "remove: honours MISE_DATA_DIR, which is where mise would have put it" {
  local elsewhere="$HOME/custom-mise"
  mkdir -p "$elsewhere"
  run env DOT_ROOT="$DOT_ROOT" HOME="$HOME" MISE_DATA_DIR="$elsewhere" \
    XDG_DATA_HOME="$HOME/.local/share" DOT_DRY_RUN=0 \
    DOT_MODULE=dev-cli DOT_MODULE_DIR="$DOT_ROOT/modules/dev-cli" \
    "$BASH" "$DOT_ROOT/modules/dev-cli/remove.sh"
  [[ $output == *"custom-mise"* ]]
}

@test "remove: a dry run prints the same words and writes nothing" {
  mkdir -p "$HOME/.local/share/mise" "$HOME/go/pkg/mod"
  local before real
  before=$(home_snapshot)

  remove
  real=$output

  remove 1
  [ "$output" = "$real" ]
  [ "$(home_snapshot)" = "$before" ]
}
