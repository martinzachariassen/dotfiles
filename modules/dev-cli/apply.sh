#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

if [[ $DOT_DRY_RUN != 1 ]] && ! command -v mise >/dev/null 2>&1; then
  fail mise 'not installed -- its Brewfile line did not apply. Run: dot apply'
  exit 1
fi

lock="${DOT_MODULE_DIR:-$(dirname "$0")}/home/.config/mise/mise.lock"
mise_data=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}

# Read from disk, as doctor.sh does: `mise ls` creates directories.
locked=0 missing=()
while read -r tool version; do
  locked=$((locked + 1))
  [[ -d $mise_data/installs/$tool/$version ]] || missing+=("$tool $version")
done < <(
  awk '/^\[\[tools\./ { t = $0; sub(/^\[\[tools\./, "", t); sub(/\]\]$/, "", t); next }
    t != "" && $1 == "version" { v = $3; gsub(/"/, "", v); print t, v; t = "" }' "$lock" 2>/dev/null
)

if ((locked > 0 && ${#missing[@]} == 0)); then
  ok mise "$(ui_count "$locked" runtime) match mise.lock"
  exit 0
fi

if ((locked == 0)); then
  info mise 'install the runtimes locked in ~/.config/mise/mise.lock'
else
  for row in "${missing[@]}"; do info runtime "$row"; done
fi
if [[ $DOT_DRY_RUN == 1 ]]; then exit 0; fi

mise install --locked --yes 2>&1 | sed '/already installed/d' | ui_quote
ok mise 'runtimes installed'
