#!/usr/bin/env bats

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

stub() {
  BIN=${BIN:-$DOT_TMP/bin}
  mkdir -p "$BIN"
  local name
  for name in "$@"; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN/$name"
    chmod +x "$BIN/$name"
  done
}

fixture_devcli() {
  MODULE_DIR="$DOT_TMP/dev-cli"
  mkdir -p "$MODULE_DIR/data"
  cp -R "$DOT_ROOT/modules/dev-cli/home" "$MODULE_DIR/home"
  {
    printf '# a fixture, not the shipped table\n\n'
    if (($#)); then printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; fi
  } >"$MODULE_DIR/data/signin.tsv"
}

WIDGET_ROW=(widget widget .config/widget/creds '"token"' 'widget login' 'every widget you own')

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
  [[ $output == *"installing node"* ]]
  [[ $output == *"installing python"* ]]
  [[ $(grep 'installing node' <<<"$output") =~ ^[[:space:]]{4,} ]]
  says mise 'runtimes installed'
}

@test "apply: mise installs from the lock, never resolving a version itself" {
  with_mise "printf '%s\\n' \"\$*\" >'$DOT_TMP/mise-args'; exit 0"

  apply
  [ "$status" -eq 0 ]
  [[ $(cat "$DOT_TMP/mise-args") == "install --locked "* ]]
}

@test "lock: every runtime config.toml asks for is in mise.lock" {
  local tool missing=()
  while IFS= read -r tool; do
    [[ -z $tool ]] && continue
    grep -qxF "[[tools.$tool]]" "$DOT_ROOT/modules/dev-cli/home/.config/mise/mise.lock" ||
      missing+=("$tool")
  done < <(toml_list "$DOT_ROOT/modules/dev-cli/home/.config/mise/config.toml" 'tools.keys()')
  [ ${#missing[@]} -eq 0 ] || {
    echo "not in mise.lock: ${missing[*]} -- run: mise lock --global (in the repo)"
    return 1
  }
}

@test "apply: a mise that fails takes the hook down with it" {
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
  says mise 'install the runtimes locked in ~/.config/mise/mise.lock'
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

@test "doctor: a credential store on disk is a CLI that is signed in" {
  with_mise 'exit 0'
  with_runtimes
  stub widget
  fixture_devcli "${WIDGET_ROW[@]}"
  mkdir -p "$HOME/.config/widget"
  printf '{"token": "abc"}\n' >"$HOME/.config/widget/creds"

  doctor
  [ "$status" -eq 0 ]
  says widget 'signed in'
}

@test "doctor: a store that survived a logout is not a sign-in" {
  with_mise 'exit 0'
  with_runtimes
  stub widget
  fixture_devcli "${WIDGET_ROW[@]}"
  mkdir -p "$HOME/.config/widget"
  printf '{"usage": 12, "clientId": "not-a-credential"}\n' >"$HOME/.config/widget/creds"

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"widget login"* ]]
}

@test "doctor: the pattern is matched inside a store that is not text" {
  with_mise 'exit 0'
  with_runtimes
  stub widget
  fixture_devcli "${WIDGET_ROW[@]}"
  mkdir -p "$HOME/.config/widget"
  printf 'SQLite format 3\000\000\001{"token": "abc"}\000\000\n' \
    >"$HOME/.config/widget/creds"

  doctor
  [ "$status" -eq 0 ]
  says widget 'signed in'
}

@test "doctor: the table has six columns on every row" {
  local line
  while IFS= read -r line; do
    [[ -n $line && $line != '#'* ]] || continue
    [ "$(awk -F'\t' '{ print NF }' <<<"$line")" -eq 6 ] || {
      echo "not six columns: $line"
      return 1
    }
  done <"$DOT_ROOT/modules/dev-cli/data/signin.tsv"
}

@test "doctor: every shipped row's pattern is an ERE grep accepts" {
  local cmd pattern
  while IFS=$'\t' read -r cmd _ _ pattern _; do
    [[ -n $cmd && $cmd != '#'* ]] || continue
    printf '\n' | grep -qaE -- "$pattern" || [ "$?" -eq 1 ] || {
      echo "$cmd has a pattern grep will not compile: $pattern"
      return 1
    }
  done <"$DOT_ROOT/modules/dev-cli/data/signin.tsv"
}

@test "doctor: no mise still runs every sign-in check" {
  local dir f path='' nomise="$DOT_TMP/nomise" dirs
  mkdir -p "$nomise"
  IFS=: read -ra dirs <<<"$PATH"
  for dir in "${dirs[@]}"; do
    if [[ -x $dir/mise ]]; then
      for f in "$dir"/*; do
        if [[ ${f##*/} != mise ]]; then ln -sf "$f" "$nomise/"; fi
      done
    else
      path+=":$dir"
    fi
  done
  stub widget
  fixture_devcli "${WIDGET_ROW[@]}"

  run env PATH="$BIN:$nomise$path" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    XDG_DATA_HOME="$HOME/.local/share" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" \
    DOT_MODULE=dev-cli DOT_MODULE_DIR="$MODULE_DIR" \
    "$BASH" "$DOT_ROOT/modules/dev-cli/doctor.sh"
  [ "$status" -eq 1 ]
  [[ $output == *"mise"*"not installed"* ]]
  [[ $output == *"widget login"* ]]
}

@test "doctor: a CLI with no credentials names the login command" {
  with_mise 'exit 0'
  with_runtimes
  stub widget
  fixture_devcli widget widget .config/widget/creds '"token"' 'widget login --scopes all' 'the widgets'

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"widget login --scopes all"* ]]
}

@test "doctor: what the missing sign-in costs is printed, not just filed" {
  with_mise 'exit 0'
  with_runtimes
  stub widget
  fixture_devcli "${WIDGET_ROW[@]}"

  doctor
  [[ $output == *"every widget you own"* ]]
}

@test "doctor: every shipped row says what it costs" {
  local cmd costs
  while IFS=$'\t' read -r cmd _ _ _ _ costs; do
    [[ -n $cmd && $cmd != '#'* ]] || continue
    [ -n "$costs" ] || {
      echo "$cmd has no column 6"
      return 1
    }
  done <"$DOT_ROOT/modules/dev-cli/data/signin.tsv"
}

@test "doctor: the path it looked at is named, because that is the weak half" {
  with_mise 'exit 0'
  with_runtimes
  stub widget
  fixture_devcli "${WIDGET_ROW[@]}"

  doctor
  [[ $output == *".config/widget/creds"* ]]
}

@test "doctor: a CLI this machine does not have is not a row it must answer" {
  with_mise 'exit 0'
  with_runtimes
  fixture_devcli "${WIDGET_ROW[@]}"

  doctor
  [ "$status" -eq 0 ]
  [[ $output != *widget* ]]
}

@test "doctor: an empty credential file is not a sign-in" {
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
