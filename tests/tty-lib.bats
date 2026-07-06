#!/usr/bin/env bats
# Tests for scripts/lib/tty.sh — reattaches a chezmoi hook's stdin to the
# controlling terminal (chezmoi runs run_* scripts with stdin closed).
#
# The reattach itself is environment-dependent (there may be no controlling tty),
# and driving both branches deterministically needs a real/absent terminal — so,
# like tty.sh's callers, we pin the contract that IS stable: the source guard
# (re-sourcing is a cheap no-op) and that tty_reattach exists and is callable
# without crashing. A deleted/renamed helper — the realistic regression, since
# several hooks source it by name — fails here.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TTY="$REPO_ROOT/scripts/lib/tty.sh"
    [ -r "$TTY" ] || skip "tty.sh not found at $TTY"
}

@test "tty.sh defines tty_reattach" {
    run bash -c "source '$TTY'; declare -F tty_reattach >/dev/null && echo ok"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "tty.sh sets its source guard and is safe to re-source" {
    run bash -c "source '$TTY'; source '$TTY'; echo \"\${__DOTFILES_TTY_SH:-unset}\""
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

# The reattach behaviour (exec </dev/tty) is deliberately NOT asserted here:
# whether /dev/tty is openable is environment-dependent, and a failed exec
# redirect legitimately terminates the (non-interactive) shell — so there's no
# stable, non-flaky behavioural assertion to make. The guard + definition above
# catch the realistic regression (a hook sourcing a deleted/renamed helper).
