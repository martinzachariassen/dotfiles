#!/usr/bin/env bash
# chez doctor — the read-only health check.
#
# This file is the runner, not the checks. It owns the tallies, the running
# order and the summary; every check lives with the feature it belongs to, as a
# sourced fragment defining one doctor_<name>() function.
#
# Sourced rather than executed, deliberately: a fragment calls pass/warn/note/
# fail directly and the counts stay in one process. Executing them would mean
# parsing exit codes back out of fifteen subprocesses to rebuild the same four
# numbers.
#
# Order is a number, never a directory name. FEATURE_DOCTOR_ORDER in each
# feature.sh places that feature's section; the checks under checks/ carry their
# own order in the filename and merge into the same scale. The current order is
# deliberate — repo, chezmoi, layout, identity, packages, runtimes, optional
# modules, informational — and alphabetical would scramble it.

# Tildes below are display text, not paths — leave them literal.
# shellcheck disable=SC2088
set -uo pipefail

# Two roots, and they are not the same thing. ROOT is where this code lives, so
# it is always resolved from this file — the libs and the check fragments are
# siblings of it. SOURCE_DIR is the repo being *checked*, which DOTFILES_DIR
# overrides so a test can point the report at a scratch worktree. Collapsing the
# two would make DOTFILES_DIR relocate the engine as well as the subject, and
# every doctor test would be running against an empty directory.
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$_DIR/../.." && pwd)"

# ui.sh is a committed sibling; fail loudly if a checkout is missing it.
if [ ! -r "$ROOT/core/ui.sh" ]; then
    printf 'doctor: missing %s\n' "$ROOT/core/ui.sh" >&2
    exit 1
fi
# shellcheck source=../../core/ui.sh
. "$ROOT/core/ui.sh"
ui_init_status
# shellcheck source=../../core/features.sh
. "$ROOT/core/features.sh"

# ── the engines the fragments read through ───────────────────────────────────
# Sourced unconditionally. These used to be `if [ -r … ]` guards, which turned a
# moved file into silence: features/brew/lib/tiers.sh was renamed out from under
# a stale path and the Homebrew section spent a release reporting "could not
# resolve active Brewfiles" and then a green "no untracked brew packages"
# derived from an empty set. A missing engine is a broken checkout, so say so.
for _lib in \
    core/chezmoi-data.sh \
    core/semver.sh \
    core/paths.sh \
    features/brew/lib/tiers.sh \
    features/vscode/lib.sh \
    features/sign/lib.sh \
    features/xcode/probe.sh \
    features/distill/lib.sh; do
    if [ ! -r "$ROOT/$_lib" ]; then
        printf 'doctor: missing %s — this checkout is incomplete\n' "$ROOT/$_lib" >&2
        exit 1
    fi
    # An engine that loads only halfway is the same problem one layer down: an
    # engine may itself refuse to load (tiers.sh does, without core/paths.sh),
    # and a half-loaded engine is exactly the green-pass-from-nothing this loop
    # exists to prevent.
    # shellcheck source=/dev/null
    if ! . "$ROOT/$_lib"; then
        printf 'doctor: %s failed to load — this checkout is incomplete\n' "$ROOT/$_lib" >&2
        exit 1
    fi
done
unset _lib

echo
printf '%s%s%s %sHealth check%s\n' "$BOLD" "$BLUE" "$NODE" "$BOLD" "$RESET"
explain \
    "Checks the repo, Homebrew, auth, signing, runtimes and shell layout." \
    "Read-only: it reports problems and how to fix them, and changes nothing."

PASS=0
ACTION=0
INFOCOUNT=0
FAIL=0

# Thin wrappers over ui.sh printers that also bump the summary tallies.
pass() {
    s_pass "$1"
    PASS=$((PASS + 1))
}
warn() {
    s_warn "$1"
    ACTION=$((ACTION + 1))
}
note() {
    s_note "$1"
    INFOCOUNT=$((INFOCOUNT + 1))
}
fail() {
    s_fail "$1"
    FAIL=$((FAIL + 1))
}
section() { s_section "$1"; }

SOURCE_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"

# ── the running order ────────────────────────────────────────────────────────

# doctor_plan — "ORDER KIND REF" per line, ascending. Two kinds share one scale:
#   feature <name>   → features/<name>/doctor.sh, ordered by its manifest
#   check   <path>   → features/doctor/checks/NN-*.sh, ordered by its filename
doctor_plan() {
    local order name f base
    while read -r order name; do
        [ -n "$order" ] || continue
        printf '%s feature %s\n' "$order" "$name"
    done < <(feature_doctor_order "$ROOT")
    for f in "$_DIR"/checks/[0-9]*.sh; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        order="${base%%-*}"
        # A leading zero would make sort -n treat it as decimal anyway, but strip
        # it so the number in the filename reads as the number in the manifest.
        order="$((10#$order))"
        printf '%s check %s\n' "$order" "$f"
    done
}

DATA_JSON="$(cm_data_json)"

while read -r _order _kind _ref; do
    case "$_kind" in
        feature)
            fragment="$ROOT/features/$_ref/doctor.sh"
            [ -f "$fragment" ] || continue
            feature_active "$ROOT" "$_ref" "$DATA_JSON" || continue
            # shellcheck source=/dev/null
            . "$fragment"
            "doctor_$_ref"
            ;;
        check)
            # shellcheck source=/dev/null
            . "$_ref"
            # 05-source-repo.sh defines doctor_check_source_repo: drop the order
            # prefix, and dashes become underscores because a function name
            # cannot carry one.
            base="$(basename "$_ref" .sh)"
            "doctor_check_$(printf '%s' "${base#*-}" | tr '-' '_')"
            ;;
    esac
done < <(doctor_plan | sort -n -k1,1)

echo
echo "${BOLD}${RULE} Summary ${RULE}${RESET}"
echo "  ${GREEN}${PASS} pass${RESET}   ${YELLOW}${ACTION} action${RESET}   ${BLUE}${INFOCOUNT} info${RESET}   ${RED}${FAIL} fail${RESET}"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
