#!/usr/bin/env bats
# Unit tests for scripts/lib/vscode.sh — the pure set logic behind the VS Code
# extension mirror (install + prune). No `code` CLI is involved, so these run on
# the Linux CI runner where the runtime 03-vscode hook cannot.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=../scripts/lib/vscode.sh
    . "$REPO_ROOT/scripts/lib/vscode.sh"
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

# ─── vscode_orphaned_home_dirs (the 03b HOME-prune set) ────────────────────────
# ROWS are "dir<TAB>extension" lines (extension-owned HOME dirs, from cleanup.owners);
# INSTALLED is raw `code --list-extensions`. Emit each dir whose extension is gone.

@test "vscode_orphaned_home_dirs returns nothing when every extension is installed" {
    local rows
    rows="$(printf '%s\n' ".lemminx"$'\t'"redhat.vscode-xml" ".sonarlint"$'\t'"sonarsource.sonarlint-vscode")"
    run vscode_orphaned_home_dirs "$rows" $'redhat.vscode-xml\nsonarsource.sonarlint-vscode'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "vscode_orphaned_home_dirs returns the dir whose extension is gone" {
    local rows
    rows="$(printf '%s\n' ".lemminx"$'\t'"redhat.vscode-xml" ".sonarlint"$'\t'"sonarsource.sonarlint-vscode")"
    run vscode_orphaned_home_dirs "$rows" $'sonarsource.sonarlint-vscode'
    [ "$status" -eq 0 ]
    [ "$output" = ".lemminx" ]
}

@test "vscode_orphaned_home_dirs matches case-insensitively (installed list mixed-case)" {
    # `code --list-extensions` can report a different case; a mixed-case installed
    # ID must still count as present, not look orphaned.
    run vscode_orphaned_home_dirs ".lemminx"$'\t'"redhat.vscode-xml" $'RedHat.vscode-XML'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "vscode_orphaned_home_dirs lowercases the map's own extension ID too" {
    run vscode_orphaned_home_dirs ".lemminx"$'\t'"RedHat.vscode-XML" $'redhat.vscode-xml'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "vscode_orphaned_home_dirs returns every dir when nothing is installed" {
    local rows
    rows="$(printf '%s\n' ".lemminx"$'\t'"redhat.vscode-xml" ".sonarlint"$'\t'"sonarsource.sonarlint-vscode")"
    run vscode_orphaned_home_dirs "$rows" ""
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "vscode_orphaned_home_dirs with empty rows returns nothing" {
    run vscode_orphaned_home_dirs "" $'redhat.vscode-xml'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── in-sync: no drift in either direction ─────────────────────────────────────

@test "identical sets (any case/order) report no drift" {
    run vscode_untracked $'a.one\nb.two' $'B.Two\nA.One'
    [ -z "$output" ]
    run vscode_missing $'a.one\nb.two' $'B.Two\nA.One'
    [ -z "$output" ]
}
