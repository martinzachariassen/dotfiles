#!/usr/bin/env bash
#
# apply.sh downloads on every run, and a half-finished download leaves a
# working shell: a missing runtime surfaces as "command not found" for a
# language you thought you had, a missing gopls as a VS Code with no
# IntelliSense and no error anywhere. Nothing else looks at either.
#
# Read-only, and it has to get there WITHOUT asking mise. `mise ls` creates
# ~/.local/share/mise and ~/.local/state/mise on a machine that has neither --
# the same trap `colima status` set in modules/containers, and contract.bats
# snapshots $HOME around every doctor.sh. The install tree is the evidence.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/go-tools.txt"

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

# `mise exec -- go install` puts these under installs/go/<version>/bin, so the
# glob spans a go upgrade without naming a version. compgen, not ls: a builtin,
# and an unmatched glob is a status rather than a subprocess and an error line.
absent=()
while IFS= read -r pkg; do
  if [[ -z $pkg || $pkg == '#'* ]]; then continue; fi
  bin=${pkg%@*}
  bin=${bin##*/}
  if ! compgen -G "$mise_data/installs/go/*/bin/$bin" >/dev/null; then
    absent+=("$bin")
  fi
done <"$data"

if ((${#absent[@]} == 0)); then
  ok 'go tools     every tool in data/go-tools.txt is installed'
else
  fail "go tools     not installed: ${absent[*]} -- run: dot apply"
fi
