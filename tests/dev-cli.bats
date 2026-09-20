#!/usr/bin/env bats
#
# modules/dev-cli. apply.sh downloads runtimes into a tree full of other
# projects' content, so nothing here is deletable -- the warning IS the
# deliverable, the same trade macos-defaults makes. doctor.sh answers two
# questions about a fresh machine: are the runtimes down, and are the CLIs
# logged in.

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

doctor() {
  run env PATH="${BIN:-$DOT_TMP/bin}:$PATH" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    XDG_DATA_HOME="$HOME/.local/share" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" \
    DOT_MODULE=dev-cli DOT_MODULE_DIR="${MODULE_DIR:-$DOT_ROOT/modules/dev-cli}" \
    "$BASH" "$DOT_ROOT/modules/dev-cli/doctor.sh"
}

# stub NAME... -- a command that exists on PATH and does nothing. doctor.sh
# only ever asks `command -v`, so a row's branch is decided by the credential
# file, never by what the tool would have said.
stub() {
  BIN=${BIN:-$DOT_TMP/bin}
  mkdir -p "$BIN"
  local name
  for name in "$@"; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN/$name"
    chmod +x "$BIN/$name"
  done
}

# fixture_devcli [CMD PKG PATH LOGIN WHY] -- a copy of the module carrying its
# own sign-in table, one row, or with no arguments a table holding nothing but
# a comment and a blank line.
#
# DOT_MODULE_DIR is where the hook finds BOTH data files, so a row naming a
# command no machine has is reachable without building an unreal PATH --
# doctor.sh needs dasel on it, and a PATH stripped down to stubs takes that
# away too. The shipped table is held against the Brewfile by contract.bats.
#
# The columns are joined here rather than written as a heredoc: a literal tab
# in this file is one editor away from being spaces, and the row would then
# parse as a command with a very long name.
fixture_devcli() {
  MODULE_DIR="$DOT_TMP/dev-cli"
  mkdir -p "$MODULE_DIR/data"
  cp -R "$DOT_ROOT/modules/dev-cli/home" "$MODULE_DIR/home"
  {
    printf '# a fixture, not the shipped table\n\n'
    if (($#)); then printf '%s\t%s\t%s\t%s\t%s\n' "$@"; fi
  } >"$MODULE_DIR/data/signin.tsv"
}

# The fixture row every sign-in test uses, so each one says only what it is
# about. `widget` is a command no machine has unless `stub` put it there.
WIDGET_ROW=(widget widget .config/widget/creds 'widget login' 'every widget you own')

# Every runtime mise's config pins, present in the install tree: a sign-in test
# must not be reading a report about missing runtimes.
with_runtimes() {
  local tool
  while IFS= read -r tool; do
    if [[ -n $tool ]]; then mkdir -p "$HOME/.local/share/mise/installs/$tool"; fi
  done < <(toml_list "$DOT_ROOT/modules/dev-cli/home/.config/mise/config.toml" 'tools.keys()')
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

# --- sign-ins ---------------------------------------------------------------
#
# The gap these close: `dot apply` finishes green on a fresh machine, and every
# one of these CLIs is still an hour of 401s away from working. Nothing else in
# the repo knows that installing a tool and being able to use it are two steps.

@test "doctor: a credential store on disk is a CLI that is signed in" {
  with_mise 'exit 0'
  with_runtimes
  stub widget
  fixture_devcli "${WIDGET_ROW[@]}"
  mkdir -p "$HOME/.config/widget"
  printf 'token\n' >"$HOME/.config/widget/creds"

  doctor
  [ "$status" -eq 0 ]
  says widget 'signed in'
}

@test "doctor: a CLI with no credentials names the login command" {
  # The deliverable. "not signed in" alone sends you to a man page; the exact
  # command is what makes doctor a checklist you can work down.
  with_mise 'exit 0'
  with_runtimes
  stub widget
  fixture_devcli widget widget .config/widget/creds 'widget login --scopes all' 'the widgets'

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"widget login --scopes all"* ]]
}

@test "doctor: what the missing sign-in costs is printed, not just filed" {
  # Column 5 is the reason to work the list down. A fresh machine gets one of
  # these per CLI, and "not signed in to gcloud" alone is a line you scroll
  # past -- the bill for scrolling past it arrives hours later as a 401.
  with_mise 'exit 0'
  with_runtimes
  stub widget
  fixture_devcli "${WIDGET_ROW[@]}"

  doctor
  [[ $output == *"every widget you own"* ]]
}

@test "doctor: every shipped row says what it costs" {
  # The table is the specification, and a row missing column 5 prints "what it
  # costs:" with nothing after it -- which reads as a bug in the tool.
  local cmd costs
  while IFS=$'\t' read -r cmd _ _ _ costs; do
    [[ -n $cmd && $cmd != '#'* ]] || continue
    [ -n "$costs" ] || {
      echo "$cmd has no column 5"
      return 1
    }
  done <"$DOT_ROOT/modules/dev-cli/data/signin.tsv"
}

@test "doctor: the path it looked at is named, because that is the weak half" {
  # A tool that moves its credential store would otherwise warn forever with
  # nothing on screen to say why. Naming the path makes a wrong row readable.
  with_mise 'exit 0'
  with_runtimes
  stub widget
  fixture_devcli "${WIDGET_ROW[@]}"

  doctor
  [[ $output == *".config/widget/creds"* ]]
}

@test "doctor: a CLI this machine does not have is not a row it must answer" {
  # The escape hatch: drop the package from the Brewfile and the row goes
  # quiet, instead of a machine that wants no gcloud staying yellow forever.
  with_mise 'exit 0'
  with_runtimes
  fixture_devcli "${WIDGET_ROW[@]}"

  doctor
  [ "$status" -eq 0 ]
  [[ $output != *widget* ]]
}

@test "doctor: an empty credential file is not a sign-in" {
  # gh writes an empty hosts.yml the first time it reads a config, so -e would
  # call a machine signed in for having run `gh` once.
  with_mise 'exit 0'
  with_runtimes
  stub widget
  fixture_devcli "${WIDGET_ROW[@]}"
  mkdir -p "$HOME/.config/widget"
  : >"$HOME/.config/widget/creds"

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"widget login"* ]]
}

@test "doctor: comments and blank lines in the table are not CLIs" {
  with_mise 'exit 0'
  with_runtimes
  fixture_devcli

  doctor
  [ "$status" -eq 0 ]
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
