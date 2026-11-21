#!/usr/bin/env bash
set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/defaults.tsv"

domains=''
in_force=0
while IFS=$'\t' read -r domain key type value _; do
  domains+=$domain$'\n'
  case "$type:$value" in
    bool:true) value=1 ;;
    bool:false) value=0 ;;
  esac
  if [[ $(defaults read "$domain" "$key" 2>/dev/null) == "$value" ]]; then
    in_force=1
  fi
done < <(grep -v '^[[:space:]]*\(#\|$\)' "$data" 2>/dev/null)

[[ -n $domains ]] ||
  die "cannot read ${data#"$DOT_ROOT"/}, which names the domains this warning is about"
((in_force)) || exit 0

warn 'macOS preferences were changed and cannot be put back'
dim 'Values from before this repo ran were never recorded. Domains written to:'
ui_nest
# `<<<` adds a newline of its own; a trailing one would sort a blank first.
while IFS= read -r domain; do
  dim "$domain"
done < <(sort -u <<<"${domains%$'\n'}")
ui_unnest
