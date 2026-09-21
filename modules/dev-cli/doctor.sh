#!/usr/bin/env bash
#
# A half-finished download leaves a working shell: a missing runtime is
# "command not found" for a language you thought you had.
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
  fail mise 'not installed (run: dot apply)'
  exit 1
fi

# The repo's copy, not ~/.config/mise/config.toml: fs_check_tree already
# reports the link, and this has to keep answering when it is missing. Reading
# [tools] means a runtime added to that file is checked without editing this
# hook.
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

# Installing these is one command; signing in to each is three more, and a
# fresh machine says nothing until something fails hours later with a 401.
# Answered from the credential store on disk, never by asking the tool:
# `gcloud auth list` and `firebase login:list` CREATE their config directory on
# a machine that has none. The columns are documented in the module README.
signin="${DOT_MODULE_DIR:-$(dirname "$0")}/data/signin.tsv"
while IFS=$'\t' read -r cmd _ rel pattern login costs; do
  if [[ -z $cmd || $cmd == '#'* ]]; then continue; fi
  if ! command -v "$cmd" >/dev/null 2>&1; then continue; fi

  # The pattern, not the file's size: every one of these stores keeps existing,
  # and keeps holding bytes, after a logout. Column 4 names what a login
  # writes. -a so a store that is not text still gets a yes or a no.
  if [[ -f $HOME/$rel ]] && grep -qaE -- "$pattern" "$HOME/$rel"; then
    ok "$cmd" 'signed in'
  else
    warn "$cmd" "never signed in on this machine -- run: $login"
    dim "what it costs: $costs"
    # A file is weaker evidence than a question, so name the path looked at.
    dim "no credentials in ~/$rel"
  fi
done <"$signin"
