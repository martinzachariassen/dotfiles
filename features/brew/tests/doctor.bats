#!/usr/bin/env bats
# The Homebrew section of `chez doctor`.
#
# The resolver itself lives in features/brew/lib/tiers.sh and is exercised in
# features/brew/tests/tiers.bats. What matters here is that the report keeps
# using it for BOTH directions — "is my active set installed?" and "what is
# installed that no active tier declares?". They used to disagree: the first was
# profile/module-gated, the second globbed every `Brewfile.*` that existed, so
# the report called a work-only cask tracked on a personal machine.

setup() {
    load '../../../core/testing/helper'
    FRAGMENT="$REPO_ROOT/features/brew/doctor.sh"
}

@test "both directions read the same active tier set" {
    grep -qE 'active_files="\$\(brew_active_files "\$DATA_JSON"' "$FRAGMENT"
    # The old code globbed features/brew/Brewfile.* for the untracked check,
    # which counts every tier that exists — including the other profile's.
    no_match 'features/brew/Brewfile\.\*' "$FRAGMENT"
    grep -qF 'tracked_files+=("$SOURCE_DIR/$rel")' "$FRAGMENT"
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
    # Both sides must go through the one shared normaliser in tiers.sh.
    # the installed side …
    grep -qF 'brew leaves 2>/dev/null | brew_bare_names' "$FRAGMENT"
    # … and the declared side, immediately after the Brewfile lines are parsed.
    grep -qE '^ +brew_bare_names\)$' "$FRAGMENT"
    no_match "awk -F/ '\{print \\\$NF\}'" "$FRAGMENT"
}
