# shellcheck shell=bash

setup_sandbox() {
  DOT_TMP=$(mktemp -d)
  export DOT_TMP

  export HOME="$DOT_TMP/home"
  export DOT_STATE="$DOT_TMP/state"
  export DOT_CONFIG="$DOT_TMP/config.toml"
  export DOT_DRY_RUN=0
  mkdir -p "$HOME"

  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"

  local kept=() dir
  while IFS= read -r dir; do
    if [[ $dir != */mise/shims ]]; then kept+=("$dir"); fi
  done < <(tr ':' '\n' <<<"$PATH")
  PATH=$(
    IFS=:
    printf '%s' "${kept[*]}"
  )
  export PATH

  DOT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DOT_ROOT
  # shellcheck source=../lib/dot.sh
  source "$DOT_ROOT/lib/dot.sh"

  DOT_N_LINKED=0 DOT_N_RELINKED=0 DOT_N_BACKED_UP=0 DOT_N_UNCHANGED=0
  DOT_FAILURES=0 DOT_WARNINGS=0

  export DOT_RUN_ID="test-$BATS_TEST_NUMBER"
}

teardown_sandbox() {
  [[ -n ${DOT_TMP:-} && -d $DOT_TMP ]] && rm -rf "$DOT_TMP"
  return 0
}

says() {
  local squeezed
  squeezed=$(tr -s ' ' <<<"$output")
  [[ $squeezed == *"$1 $2"* ]]
}

home_snapshot() {
  local p
  find "$HOME" -path "$HOME/Library" -prune -o -print0 | sort -z |
    while IFS= read -r -d '' p; do
      if [[ -L $p ]]; then
        printf 'link %s -> %s\n' "$p" "$(readlink "$p")"
      elif [[ -f $p ]]; then
        printf 'file %s %s\n' "$p" "$(shasum -a 256 <"$p" | cut -d' ' -f1)"
      else
        printf 'node %s\n' "$p"
      fi
    done
}

fixture_module() {
  local dir="$DOT_TMP/modules/$1"
  mkdir -p "$dir/home"
  printf '%s\n' "$dir"
}

fixture_file() {
  local dir=$1 rel=$2 content=${3:-content}
  mkdir -p "$(dirname "$dir/home/$rel")"
  printf '%s\n' "$content" >"$dir/home/$rel"
}

json_parses() {
  jq -e . "$1" >/dev/null 2>&1 && return 0
  sed 's|^[[:space:]]*//.*$||' "$1" |
    perl -0pe 's/,(\s*[}\]])/$1/g' |
    jq -e . >/dev/null 2>&1
}

pass_core_checks() {
  DOT_DRY_RUN=0 bash "$DOT_ROOT/core/apply.sh" >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
}
