#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

mise_data=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}

if command -v mise >/dev/null 2>&1; then
  config="${DOT_MODULE_DIR:-$(dirname "$0")}/home/.config/mise/config.toml"
  missing=()
  while IFS= read -r tool; do
    if [[ -n $tool && ! -d $mise_data/installs/$tool ]]; then missing+=("$tool"); fi
  done < <(toml_list "$config" 'tools.keys()')

  if ((${#missing[@]} == 0)); then
    ok runtimes 'every tool in mise config.toml is installed'
  else
    fail runtimes "not installed: ${missing[*]} -- run: dot apply"
  fi
else
  fail mise 'not installed (run: dot apply)'
fi

signin="${DOT_MODULE_DIR:-$(dirname "$0")}/data/signin.tsv"
while IFS=$'\t' read -r cmd _ rel pattern login costs; do
  if [[ -z $cmd || $cmd == '#'* ]]; then continue; fi
  if ! command -v "$cmd" >/dev/null 2>&1; then continue; fi

  # Read from disk, never by asking the tool: `gcloud auth list` creates its
  # config dir. The pattern, not the file: every store outlives a logout.
  if [[ -f $HOME/$rel ]] && grep -qaE -- "$pattern" "$HOME/$rel"; then
    ok "$cmd" 'signed in'
  else
    warn "$cmd" "never signed in on this machine -- run: $login"
    dim "what it costs: $costs"
    dim "no credentials in ~/$rel"
  fi
done <"$signin"
