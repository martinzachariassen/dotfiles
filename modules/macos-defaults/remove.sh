#!/usr/bin/env bash
#
# Nothing to undo: apply.sh never read the old values, and `defaults delete`
# would give Apple's factory setting, not what you had. Reversing this needs a
# state file, a trade this repo has not made. A warning is all there is.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/defaults.tsv"

# One pass, two answers, both derived so neither can go stale. `domains` is
# what the warning lists: typed out, a domain apply.sh gains is a lie with
# nothing to catch it. `in_force` is whether to warn at all -- uninstall.sh
# runs every remove.sh, enabled or not, and on a machine that never ran this
# module the same words are that lie. A row is read as doctor.sh reads it.
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

# Tested before the warning, never inside it: an unreadable table used to print
# the "cannot be put back" line with no domains under it. A process
# substitution, not `<"$data"`, so a missing file arrives here, not as a crash.
[[ -n $domains ]] ||
  die "cannot read ${data#"$DOT_ROOT"/}, which names the domains this warning is about"
((in_force)) || exit 0

warn 'macOS preferences were changed and cannot be put back'
dim 'Values from before this repo ran were never recorded. Domains written to:'
# `<<<` adds a newline of its own; the trailing one would sort a blank first.
while IFS= read -r domain; do
  dim "  $domain"
done < <(sort -u <<<"${domains%$'\n'}")
