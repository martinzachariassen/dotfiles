#!/usr/bin/env bats
# Unit tests for scripts/lib/active-modules.sh.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=../scripts/lib/active-modules.sh
    . "$REPO_ROOT/scripts/lib/active-modules.sh"
}

@test "personal + macApps: core, mac-apps, personal — in order" {
    run active_modules personal true
    [ "${lines[0]}" = "Brewfile" ]
    [ "${lines[1]}" = "brewfiles/Brewfile.mac-apps" ]
    [ "${lines[2]}" = "brewfiles/Brewfile.personal" ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "work without macApps: core + work only" {
    run active_modules work false
    [ "${lines[0]}" = "Brewfile" ]
    [ "${lines[1]}" = "brewfiles/Brewfile.work" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "BASEDIR prefixes every module with an absolute path" {
    run active_modules personal true /src
    [ "${lines[0]}" = "/src/Brewfile" ]
    [ "${lines[1]}" = "/src/brewfiles/Brewfile.mac-apps" ]
    [ "${lines[2]}" = "/src/brewfiles/Brewfile.personal" ]
}

@test "defaults (no args) resolve to personal + macApps" {
    run active_modules
    [ "${lines[0]}" = "Brewfile" ]
    [ "${lines[1]}" = "brewfiles/Brewfile.mac-apps" ]
    [ "${lines[2]}" = "brewfiles/Brewfile.personal" ]
}
