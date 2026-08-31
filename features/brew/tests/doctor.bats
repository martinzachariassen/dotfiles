#!/usr/bin/env bats
# The Homebrew section of `chez doctor`.
#
# The resolver itself lives in features/brew/lib/tiers.sh and is exercised in
# features/brew/tests/tiers.bats. What matters here is that the report keeps
# using it for BOTH directions — "is my active set installed?" and "what is
# installed that no active tier declares?". They used to disagree: the first
# asked the resolver, the second globbed every `Brewfile.*` on disk, so a tier
# this machine does not enable still vouched for whatever it declared.

setup() {
    load '../../../core/testing/helper'
    FRAGMENT="$REPO_ROOT/features/brew/doctor.sh"
}

@test "both directions read the same active tier set" {
    grep -qE 'active_files="\$\(brew_active_files "\$DATA_JSON"' "$FRAGMENT"
    # The old code globbed features/brew/Brewfile.* for the untracked check,
    # which counts every tier that exists — including ones nothing enables.
    no_match 'features/brew/Brewfile\.\*' "$FRAGMENT"
    # Through brew_resolve_file, not by prefixing the repo root by hand. A repo
    # tier is repo-relative and the machine-local overlay is absolute, so a bare
    # "$SOURCE_DIR/$rel" turns the overlay into a path that does not exist —
    # silently dropping it, which reports every locally adopted package as
    # untracked. One resolver, so no caller can get half the rule.
    grep -qF 'abs="$(brew_resolve_file "$SOURCE_DIR" "$rel")"' "$FRAGMENT"
    no_match 'tracked_files\+=\("\$SOURCE_DIR/\$rel"\)' "$FRAGMENT"
}

@test "the overlay is reported, and only when it declares something" {
    # It lives outside the checkout, so it appears in no diff and no git status;
    # doctor is the only place it ever surfaces. But it is seeded on every Mac,
    # so its mere existence must not print a line.
    grep -qF 'chez_local_brewfile' "$FRAGMENT"
    grep -qF '[ "${n_local:-0}" -gt 0 ]' "$FRAGMENT"
}

@test "the empty tier set is guarded before grepping (no stdin hang)" {
    # `grep -h PATTERN` with zero file operands reads stdin and hangs the run.
    grep -qF '[ "${#tracked_files[@]}" -eq 0 ]' "$FRAGMENT"
}

# The runner sources features/brew/lib/tiers.sh unconditionally and dies if it
# is missing. It used to be an `if [ -r … ]` guard, and when the file was
# renamed under it the section reported "could not resolve active Brewfiles"
# followed by a green "no untracked brew packages" — a pass derived from an
# empty set, which is the worst possible answer.
@test "the resolver is a hard dependency of the report, not an optional one" {
    local runner="$REPO_ROOT/features/doctor/cli.sh"
    grep -qF 'features/brew/lib/tiers.sh' "$runner"
    no_match 'if \[ -r .*tiers\.sh' "$runner"
    grep -qF 'this checkout is incomplete' "$runner"
}

@test "the fragment reads the resolver rather than reimplementing tier selection" {
    # A second copy of the tier logic is how the two directions drifted apart
    # the first time.
    no_match 'byProfile|byModule' "$FRAGMENT"
}

@test "both sides of the untracked check are normalised the same way" {
    # The asymmetry this guards: the Brewfile side was piped through
    # `awk -F/ '{print $NF}'` and the `brew leaves` side was not, so a formula
    # installed from a tap (hashicorp/tap/terraform vs terraform) could never
    # match its own declaration and was reported as untracked on every run.
    # Both sides now meet inside brew_untracked_of_kind, which normalises each
    # through brew_bare_names; the fragment must not re-parse Brewfiles itself.
    no_match "awk -F/ '\{print \\\$NF\}'" "$FRAGMENT"
    no_match 'sed -E .s/\^\(brew' "$FRAGMENT"
    grep -qF 'brew_untracked_of_kind' "$FRAGMENT"
}

@test "the untracked check covers casks, not just formulae" {
    # `brew leaves` lists formulae only, so for a long time an installed cask
    # that no active tier declared was invisible to doctor while chez status
    # and chez mirror both reported it. The two sides must be asked separately,
    # because a merged namespace lets a declared cask vouch for an undeclared
    # formula of the same name (docker ships as both).
    grep -qF 'brew_untracked_of_kind brew' "$FRAGMENT"
    grep -qF 'brew_untracked_of_kind cask' "$FRAGMENT"
    grep -qF 'brew list --cask' "$FRAGMENT"
}
