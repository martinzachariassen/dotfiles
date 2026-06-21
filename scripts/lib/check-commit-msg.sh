#!/usr/bin/env bash
# check-commit-msg.sh — validate a commit message subject against this repo's
# Conventional Commits rule. CI enforces the same shape on PR *titles*; this
# applies it to every commit, so the direct-to-main commits this repo expects
# get checked too. Wired in via the commit-msg pre-commit hook
# (.pre-commit-config.yaml); unit-tested by tests/check-commit-msg.bats.
#
# Usage: check-commit-msg.sh <path-to-commit-msg-file>

set -euo pipefail

# Keep in sync with the `types` list in .github/workflows/ci.yml (pr-title job).
types='feat|fix|docs|refactor|test|chore|perf|build|ci|style'

# The subject is the first non-comment line of the message file.
subject="$(sed -n '/^[^#]/{p;q;}' "${1:?commit message file required}")"

# git's own generated subjects (merges, reverts) and rebase fixups aren't
# author-written Conventional Commits — let them through untouched.
case "$subject" in
    "Merge "* | "Revert "* | "fixup! "* | "squash! "*) exit 0 ;;
esac

if [ "${#subject}" -gt 72 ]; then
    echo "commit-msg: subject exceeds 72 characters (${#subject})." >&2
    echo "  $subject" >&2
    exit 1
fi

# <type>(<optional scope>)<optional !>: <non-empty subject>
if ! printf '%s' "$subject" | grep -qE "^(${types})(\([^)]+\))?!?: .+"; then
    echo "commit-msg: subject must follow Conventional Commits." >&2
    echo "  expected: <type>(<scope>): <subject>" >&2
    echo "  types:    ${types//|/, }" >&2
    echo "  got:      ${subject:-<empty>}" >&2
    exit 1
fi
