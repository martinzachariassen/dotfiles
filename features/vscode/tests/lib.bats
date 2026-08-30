#!/usr/bin/env bats
# Unit tests for features/vscode/lib.sh — the pure set logic behind the VS Code
# extension mirror (install + prune). No `code` CLI is involved, so these run on
# the Linux CI runner where the runtime 03-vscode hook cannot.

setup() {
    load '../../../core/testing/helper'
    # shellcheck source=../lib.sh
    . "$REPO_ROOT/features/vscode/lib.sh"
}

# ─── vscode_normalize ──────────────────────────────────────────────────────────

@test "vscode_normalize strips comments/whitespace/blanks, lowercases, sorts" {
    output="$(printf '%s\n' '# header comment' 'Foo.Bar  ' '' 'baz.qux # trailing' | vscode_normalize)"
    [ "$output" = "$(printf '%s\n' 'baz.qux' 'foo.bar')" ]
}

@test "vscode_normalize dedupes case-insensitively" {
    output="$(printf '%s\n' 'a.one' 'A.One' 'b.two' | vscode_normalize)"
    [ "$output" = "$(printf '%s\n' 'a.one' 'b.two')" ]
}

@test "vscode_normalize on empty input yields nothing" {
    output="$(printf '' | vscode_normalize)"
    [ -z "$output" ]
}

# ─── vscode_read_manifest ──────────────────────────────────────────────────────

@test "vscode_read_manifest cleans and returns manifest IDs" {
    f="$BATS_TEST_TMPDIR/ext.txt"
    printf '%s\n' '# comment' 'Alpha.One' 'beta.two' '' >"$f"
    run vscode_read_manifest "$f"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "alpha.one" ]
    [ "${lines[1]}" = "beta.two" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "vscode_read_manifest excludes given IDs case-insensitively" {
    f="$BATS_TEST_TMPDIR/ext.txt"
    printf '%s\n' 'alpha.one' 'beta.two' 'gamma.three' >"$f"
    run vscode_read_manifest "$f" 'BETA.TWO'
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    ! printf '%s\n' "${lines[@]}" | grep -qx 'beta.two'
}

@test "vscode_read_manifest on a missing file yields nothing" {
    run vscode_read_manifest "$BATS_TEST_TMPDIR/nope.txt"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── vscode_untracked (the prune set) ──────────────────────────────────────────

@test "vscode_untracked lists installed-but-not-in-manifest" {
    run vscode_untracked $'a.one\nB.Two\nc.three' $'a.one\nc.three'
    [ "$output" = "b.two" ]
}

@test "vscode_untracked normalizes both inputs (raw code --list-extensions ok)" {
    # installed comes straight from `code --list-extensions` — mixed case.
    run vscode_untracked $'Publisher.Kept\nPublisher.Stray' $'publisher.kept'
    [ "$output" = "publisher.stray" ]
}

@test "vscode_untracked with empty installed set is empty" {
    run vscode_untracked "" $'a.one\nb.two'
    [ -z "$output" ]
}

# ─── vscode_missing ────────────────────────────────────────────────────────────

@test "vscode_missing lists manifest-but-not-installed" {
    run vscode_missing $'a.one' $'a.one\nd.four'
    [ "$output" = "d.four" ]
}

@test "vscode_missing with empty installed set lists the whole manifest" {
    run vscode_missing "" $'a.one\nb.two'
    [ "${#lines[@]}" -eq 2 ]
}

# ─── in-sync: no drift in either direction ─────────────────────────────────────

@test "identical sets (any case/order) report no drift" {
    run vscode_untracked $'a.one\nb.two' $'B.Two\nA.One'
    [ -z "$output" ]
    run vscode_missing $'a.one\nb.two' $'B.Two\nA.One'
    [ -z "$output" ]
}
