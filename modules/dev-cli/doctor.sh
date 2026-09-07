#!/usr/bin/env bash
#
# A half-finished download leaves a working shell: a missing runtime is "command
# not found" for a language you thought you had. Nothing else looks at this.
#
# Read-only WITHOUT asking mise: `mise ls` creates ~/.local/share/mise and
# ~/.local/state/mise on a machine that has neither. The install tree is the
# evidence instead.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# mise's own default resolution, which it does not expose for scripting. Same
# line as remove.sh (tests/contract.bats).
mise_data=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}

if ! command -v mise >/dev/null 2>&1; then
  fail 'mise         not installed (run: dot apply)'
  exit 1
fi

# The repo's copy, not ~/.config/mise/config.toml: fs_check_tree already
# reports the link, and this has to keep answering when it is missing. Reading
# [tools] rather than a list here means a runtime added to that file is checked
# without editing this hook.
config="${DOT_MODULE_DIR:-$(dirname "$0")}/home/.config/mise/config.toml"
missing=()
while IFS= read -r tool; do
  if [[ -n $tool && ! -d $mise_data/installs/$tool ]]; then missing+=("$tool"); fi
done < <(toml_list "$config" 'tools.keys()')

if ((${#missing[@]} == 0)); then
  ok 'runtimes     every tool in mise config.toml is installed'
else
  fail "runtimes     not installed: ${missing[*]} -- run: dot apply"
fi
