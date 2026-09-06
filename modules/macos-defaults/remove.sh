#!/usr/bin/env bash
#
# Nothing to undo: apply.sh never read the old values, and `defaults delete`
# would give Apple's factory setting, not what you had. Reversing this needs a
# state file, a trade this repo has not made.
#
# So this warning is all the user gets, which is why the domain list is cut
# from data/defaults.tsv and never typed: a domain apply.sh writes and this
# list omits is a lie about an irreversible change, with nothing to catch it.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

data="${DOT_MODULE_DIR:-$(dirname "$0")}/data/defaults.tsv"

# Cut before the warning, not inside it: an unreadable data file used to print
# the "cannot be put back" line with no domains under it -- the exact lie the
# comment above forbids -- and still exit as a plain warning.
domains=$(grep -v '^[[:space:]]*\(#\|$\)' "$data" 2>/dev/null | cut -f1 | sort -u) || true
[[ -n $domains ]] ||
  die "cannot read ${data#"$DOT_ROOT"/}, which names the domains this warning is about"

warn 'macOS preferences were changed and cannot be put back'
dim 'Values from before this repo ran were never recorded. Domains written to:'
while IFS= read -r domain; do
  dim "  $domain"
done <<<"$domains"
