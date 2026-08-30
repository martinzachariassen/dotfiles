#!/usr/bin/env bats
# Tests for core/sudo.sh, the background sudo-timestamp keeper shared by
# run_before_00-sudo-cache and macos-defaults.sh.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SUDO_LIB="$REPO_ROOT/core/sudo.sh"
    [ -r "$SUDO_LIB" ] || skip "sudo.sh not found at $SUDO_LIB"
}

@test "sudo.sh defines sudo_keep_warm" {
    run bash -c "source '$SUDO_LIB'; declare -F sudo_keep_warm >/dev/null && echo ok"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "sudo.sh sets its source guard and is safe to re-source" {
    run bash -c "source '$SUDO_LIB'; source '$SUDO_LIB'; echo \"\${__DOTFILES_SUDO_SH:-unset}\""
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "sudo_keep_warm refreshes sudo -n while the watched pid is alive" {
    STUB_DIR="$BATS_TEST_TMPDIR/stub"
    mkdir -p "$STUB_DIR"
    LOG="$BATS_TEST_TMPDIR/sudo.log"
    cat >"$STUB_DIR/sudo" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$LOG"
exit 0
EOF
    chmod +x "$STUB_DIR/sudo"

    # A watched process that stays alive for the duration of this test.
    sleep 30 &
    watch_pid=$!

    # refresh_secs=0 refreshes on every ~2s poll instead of waiting 240s.
    PATH="$STUB_DIR:$PATH" bash -c "source '$SUDO_LIB'; sudo_keep_warm $watch_pid 0"

    for _ in $(seq 1 30); do
        [ -s "$LOG" ] && break
        sleep 0.1
    done

    kill "$watch_pid" 2>/dev/null || true

    [ -s "$LOG" ]
    grep -qF -- '-n true' "$LOG"
}

@test "sudo_keep_warm stops polling once the watched pid exits" {
    STUB_DIR="$BATS_TEST_TMPDIR/stub"
    mkdir -p "$STUB_DIR"
    LOG="$BATS_TEST_TMPDIR/sudo.log"
    cat >"$STUB_DIR/sudo" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$LOG"
exit 0
EOF
    chmod +x "$STUB_DIR/sudo"

    # A watched process that exits almost immediately.
    (sleep 0.2) &
    watch_pid=$!

    PATH="$STUB_DIR:$PATH" bash -c "source '$SUDO_LIB'; sudo_keep_warm $watch_pid 0"

    # First poll (~immediate) should log one call; wait past several more poll
    # cycles (2s each) and confirm the count stops growing once the pid is gone.
    for _ in $(seq 1 30); do
        [ -s "$LOG" ] && break
        sleep 0.1
    done
    wait "$watch_pid" 2>/dev/null || true
    first_count="$(wc -l <"$LOG" | tr -d ' ')"

    sleep 5
    second_count="$(wc -l <"$LOG" | tr -d ' ')"

    [ "$first_count" -ge 1 ]
    [ "$second_count" -eq "$first_count" ]
}
