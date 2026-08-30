#!/usr/bin/env bats
# Tests for core/tty.sh, which reattaches a chezmoi hook's stdin to the
# controlling terminal (chezmoi runs run_* scripts with stdin closed). The
# reattach itself is environment-dependent, so this only pins what's stable:
# the source guard and that tty_reattach exists and is callable.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TTY="$REPO_ROOT/core/tty.sh"
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

# exec </dev/tty itself isn't tested: /dev/tty's openability is environment-
# dependent, and a failed exec legitimately kills a non-interactive shell.
