#!/usr/bin/env bats
# The mise apply hook. It is a run_after rather than a run_onchange because a
# runtime can go missing while config.toml stays put — so the branch that
# matters is what it does when it finds nothing to do, and what it does when
# mise is not installed yet. Neither may fail an apply.

setup() {
    load '../../../core/testing/helper'
    HOOK="$REPO_ROOT/features/runtimes/hook.sh"
    BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$BIN"
}

# BREW_BIN is pointed at nothing so the hook cannot pull the host's real
# Homebrew bin onto PATH — otherwise this machine's own mise would decide the
# outcome and the suite would pass or fail by accident of where it runs.
run_hook() {
    run env PATH="$BIN:/usr/bin:/bin" BREW_BIN="$BATS_TEST_TMPDIR/no-brew" \
        HOME="$BATS_TEST_TMPDIR" bash "$HOOK"
}

@test "with mise not installed yet it explains the retry and exits 0" {
    run_hook
    [ "$status" -eq 0 ]
    [[ "$output" == *"mise not on PATH yet"* ]] || return 1
    [[ "$output" == *chezup* ]] || return 1
}

@test "with nothing missing it reports the current set and installs nothing" {
    stub_bin "$BIN" mise '
case "$1 $2" in
    "ls --missing") ;;                 # nothing missing
    "current ") echo "java 25"; echo "node 22" ;;
    "install ") echo "SHOULD-NOT-INSTALL" ;;
esac'
    run_hook
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]] || return 1
    [[ "$output" == *"java 25 node 22"* ]] || return 1
    [[ "$output" != *SHOULD-NOT-INSTALL* ]] || return 1
}

@test "it counts the missing runtimes from mise itself, then installs them" {
    stub_bin "$BIN" mise '
case "$1 $2" in
    "ls --missing") [ -e "'"$BATS_TEST_TMPDIR"'/done" ] || { echo "node 22"; echo "python 3.13"; } ;;
    "install ") echo "INSTALLING"; touch "'"$BATS_TEST_TMPDIR"'/done" ;;
    "current ") echo "node 22"; echo "python 3.13" ;;
esac'
    run_hook
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installing 2 missing runtime(s): node python"* ]] || return 1
    [[ "$output" == *INSTALLING* ]] || return 1
    [[ "$output" == *"mise runtimes installed"* ]] || return 1
}

@test "a failed install is reported but never fails the apply" {
    stub_bin "$BIN" mise '
case "$1 $2" in
    "ls --missing") echo "node 22" ;;
    "install ") exit 1 ;;
esac'
    run_hook
    [ "$status" -eq 0 ]
    [[ "$output" == *"mise install failed"* ]] || return 1
}
