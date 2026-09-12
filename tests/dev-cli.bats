#!/usr/bin/env bats
#
# modules/dev-cli/remove.sh. apply.sh downloads runtimes into a tree full of
# other projects' content, so nothing here is deletable -- the warning IS the
# deliverable, the same trade macos-defaults makes.

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

# apply.sh was the one hook here with no test: on a real machine it downloads
# language runtimes, so it never ran in CI and never ran under a reviewer's
# eye either. `mise` is shadowed on PATH, which makes all three of its paths
# reachable without fetching a single toolchain.
apply() {
  run env PATH="$BIN:$PATH" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN="${1:-0}" \
    DOT_MODULE=dev-cli DOT_MODULE_DIR="$DOT_ROOT/modules/dev-cli" \
    "$BASH" "$DOT_ROOT/modules/dev-cli/apply.sh"
}

with_mise() {
  BIN="$DOT_TMP/bin"
  mkdir -p "$BIN"
  printf '#!/usr/bin/env bash\n%s\n' "$1" >"$BIN/mise"
  chmod +x "$BIN/mise"
}

@test "apply: mise's own output is kept, and the run closes on its own line" {
  with_mise 'printf "installing node\ninstalling python\n"; exit 0'

  apply
  [ "$status" -eq 0 ]
  # Kept: a download that takes minutes must be visible while it happens.
  [[ $output == *"installing node"* ]]
  [[ $output == *"installing python"* ]]
  # And set apart from this repo's own lines, which is what makes it skippable.
  [[ $(grep 'installing node' <<<"$output") =~ ^[[:space:]]{4,} ]]
  says mise 'runtimes installed'
}

@test "apply: a mise that fails takes the hook down with it" {
  # The output goes through a pipe now, so the status has to survive it.
  with_mise 'echo "could not resolve node@20"; exit 1'

  apply
  [ "$status" -ne 0 ]
  [[ $output == *"could not resolve"* ]]
  [[ $output != *"runtimes installed"* ]]
}

@test "apply: a dry run names the file it would read and installs nothing" {
  with_mise 'printf "SHOULD NOT RUN\n"; exit 0'
  local before
  before=$(home_snapshot)

  apply 1
  [ "$status" -eq 0 ]
  says mise 'install the runtimes pinned in ~/.config/mise/config.toml'
  [[ $output != *"SHOULD NOT RUN"* ]]
  [ "$(home_snapshot)" = "$before" ]
}

@test "apply: no mise at all is a failure that names the cause" {
  BIN="$DOT_TMP/empty-bin"
  mkdir -p "$BIN"
  run env PATH="$BIN" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN=0 \
    DOT_MODULE=dev-cli DOT_MODULE_DIR="$DOT_ROOT/modules/dev-cli" \
    "$BASH" "$DOT_ROOT/modules/dev-cli/apply.sh"
  [ "$status" -ne 0 ]
  [[ $output == *"Brewfile line did not apply"* ]]
}

@test "remove: says nothing on a machine that never enabled the module" {
  # uninstall.sh runs every module's remove.sh. A hook that warns about a
  # directory nobody has is noise in the one output an uninstall leaves.
  remove
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remove: names the mise tree, and refuses to delete it" {
  mkdir -p "$HOME/.local/share/mise/installs/node/20.0.0/bin"
  printf 'a real binary\n' >"$HOME/.local/share/mise/installs/node/20.0.0/bin/node"

  remove
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *".local/share/mise"* ]]
  [[ $output == *"mise implode"* ]]
  [ -f "$HOME/.local/share/mise/installs/node/20.0.0/bin/node" ]
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
  mkdir -p "$HOME/.local/share/mise"
  local before real
  before=$(home_snapshot)

  remove
  real=$output

  remove 1
  [ "$output" = "$real" ]
  [ "$(home_snapshot)" = "$before" ]
}
