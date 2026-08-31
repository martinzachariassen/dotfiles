#!/usr/bin/env bats
# The colima apply hook. Its three jobs are independent of colima itself —
# clearing the ~/.colima directory that would shadow the managed config, pruning
# the dangling cli-plugin symlinks Docker Desktop left behind, and registering
# the login agent — so all three are driven here against a scratch HOME with a
# stub colima on PATH. None of it had coverage while it lived inside the
# template; that is most of the reason it is a script now.

setup() {
    load '../../../core/testing/helper'
    HOOK="$REPO_ROOT/features/containers/hook.sh"
    FAKE_HOME="$BATS_TEST_TMPDIR/home"
    BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$FAKE_HOME" "$BIN"
    # `colima list` naming no instance keeps the run off the "existing VM" note.
    stub_bin "$BIN" colima 'exit 0'
    # The plist is deliberately absent, so the launchctl calls are never reached
    # and the hook stays runnable on a Linux CI runner.
}

run_hook() {
    run env PATH="/usr/bin:/bin" COLIMA_BIN="${1:-$BIN/colima}" \
        bash "$HOOK" "$FAKE_HOME"
}

@test "with colima not installed it says so and exits 0 without touching HOME" {
    run_hook "$BATS_TEST_TMPDIR/nope"
    [ "$status" -eq 0 ]
    [[ "$output" == *"colima not installed"* ]] || return 1
    [ ! -d "$FAKE_HOME/.local/state/colima/logs" ]
}

@test "it creates the log directory launchd will not create itself" {
    run_hook
    [ "$status" -eq 0 ]
    [ -d "$FAKE_HOME/.local/state/colima/logs" ]
}

@test "an empty ~/.colima is removed — it would shadow ~/.config/colima" {
    mkdir -p "$FAKE_HOME/.colima"
    run_hook
    [ "$status" -eq 0 ]
    [ ! -e "$FAKE_HOME/.colima" ]
    [[ "$output" == *"removed an empty ~/.colima"* ]] || return 1
}

@test "a populated ~/.colima is reported, never deleted" {
    mkdir -p "$FAKE_HOME/.colima"
    : >"$FAKE_HOME/.colima/instance-state"
    run_hook
    [ "$status" -eq 0 ]
    [ -f "$FAKE_HOME/.colima/instance-state" ]
    [[ "$output" == *"shadows ~/.config/colima"* ]] || return 1
}

@test "dangling cli-plugin symlinks are pruned and resolving ones are kept" {
    local plugins="$FAKE_HOME/.docker/cli-plugins"
    mkdir -p "$plugins"
    : >"$BATS_TEST_TMPDIR/real-plugin"
    ln -s "$BATS_TEST_TMPDIR/real-plugin" "$plugins/docker-compose"
    ln -s "$BATS_TEST_TMPDIR/gone-with-docker-desktop" "$plugins/docker-scan"
    : >"$plugins/not-a-symlink"
    run_hook
    [ "$status" -eq 0 ]
    [ -L "$plugins/docker-compose" ]
    [ ! -L "$plugins/docker-scan" ]
    [ -f "$plugins/not-a-symlink" ]
    [[ "$output" == *"pruned 1 dangling cli-plugin symlink"* ]] || return 1
}

@test "a missing plist is reported rather than registered blindly" {
    run_hook
    [ "$status" -eq 0 ]
    [[ "$output" == *"no.mlz.colima.plist missing"* ]] || return 1
}

# ─── registering the login agent ─────────────────────────────────────────────
# Re-registering is the whole point of the hook: launchd caches the loaded copy,
# so a rewritten plist changes nothing until something boots the agent out and
# back in. Both directions run against a stub launchctl — the real one would
# touch this machine's own agent.

_with_plist() {
    mkdir -p "$FAKE_HOME/Library/LaunchAgents"
    : >"$FAKE_HOME/Library/LaunchAgents/no.mlz.colima.plist"
}

@test "the agent is booted out before it is bootstrapped" {
    _with_plist
    stub_bin "$BIN" launchctl "printf '%s\n' \"\$1\" >>'$BATS_TEST_TMPDIR/launchctl.log'"
    run env PATH="$BIN:/usr/bin:/bin" COLIMA_BIN="$BIN/colima" bash "$HOOK" "$FAKE_HOME"
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent registered"* ]] || return 1
    # Order matters: a bootstrap without the preceding bootout is a no-op that
    # still exits 0, so the edited plist would silently never take effect.
    [ "$(head -1 "$BATS_TEST_TMPDIR/launchctl.log")" = bootout ]
    grep -qx bootstrap "$BATS_TEST_TMPDIR/launchctl.log"
}

@test "a failed bootstrap reports launchctl's own message, not just that it failed" {
    _with_plist
    stub_bin "$BIN" launchctl '[ "$1" = bootstrap ] || exit 0
echo "Bootstrap failed: 5: Input/output error" >&2
exit 5'
    run env PATH="$BIN:/usr/bin:/bin" COLIMA_BIN="$BIN/colima" bash "$HOOK" "$FAKE_HOME"
    # Never fails the apply — hook 99 prints the "Next moves" block after this.
    [ "$status" -eq 0 ]
    [[ "$output" == *"Bootstrap failed: 5: Input/output error"* ]] || return 1
    [[ "$output" == *"chez apply"* ]] || return 1
}
