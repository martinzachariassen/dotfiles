#!/usr/bin/env bats
# Unit tests for the pure helpers in scripts/lib/brew-bundle.sh.
# (The install/heartbeat paths hit `brew` and a real terminal, so they're
# exercised by the DRY_RUN dry-drive in docs/lifecycle.md rather than here.)

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=../scripts/lib/brew-bundle.sh
    . "$REPO_ROOT/scripts/lib/brew-bundle.sh"
}

# ─── is_bundle_line ─────────────────────────────────────────────────────────────

@test "is_bundle_line accepts tap/brew/cask/mas directives" {
    run is_bundle_line 'tap "foo/bar"';   [ "$status" -eq 0 ]
    run is_bundle_line 'brew "jq"';        [ "$status" -eq 0 ]
    run is_bundle_line 'cask "raycast"';   [ "$status" -eq 0 ]
    run is_bundle_line 'mas "Xcode", id: 1'; [ "$status" -eq 0 ]
}

@test "is_bundle_line rejects comments, blanks, and other text" {
    run is_bundle_line '# a comment';      [ "$status" -eq 1 ]
    run is_bundle_line '';                  [ "$status" -eq 1 ]
    run is_bundle_line 'echo hi';           [ "$status" -eq 1 ]
}

# ─── entry_name ─────────────────────────────────────────────────────────────────

@test "entry_name returns 'kind name' and strips trailing comments" {
    run entry_name 'cask "raycast"            # Spotlight replacement'
    [ "$output" = "cask raycast" ]
}

@test "entry_name handles tapped/namespaced formulae" {
    run entry_name 'brew "hashicorp/tap/terraform"  # IaC'
    [ "$output" = "brew hashicorp/tap/terraform" ]
}

@test "entry_name handles mas entries with an id suffix" {
    run entry_name 'mas "Xcode", id: 497799835'
    [ "$output" = "mas Xcode" ]
}

# ─── count_bundle_lines ─────────────────────────────────────────────────────────

@test "count_bundle_lines counts only actionable directives" {
    f="$BATS_TEST_TMPDIR/Brewfile"
    printf '# header\n\ntap "a/b"\nbrew "jq"\ncask "raycast"\n# trailing\n' > "$f"
    run count_bundle_lines "$f"
    [ "$output" = "3" ]
}

@test "count_bundle_lines tolerates leading whitespace" {
    f="$BATS_TEST_TMPDIR/Brewfile"
    printf '   brew "jq"\n\t cask "vlc"\n' > "$f"
    run count_bundle_lines "$f"
    [ "$output" = "2" ]
}

@test "count_bundle_lines returns 0 for a missing file" {
    run count_bundle_lines "$BATS_TEST_TMPDIR/does-not-exist"
    [ "$output" = "0" ]
}
