#!/usr/bin/env bash
# tty.sh — chezmoi runs run_* hooks with stdin closed; reattach it to /dev/tty for interactive steps (sudo, y/N).
# shellcheck disable=SC2329

[ -n "${__DOTFILES_TTY_SH:-}" ] && return 0
__DOTFILES_TTY_SH=1

# Return 0 and point stdin at /dev/tty if readable; else return 1 (caller decides).
# The open is attempted, not just stat'd: under CI and some hook contexts /dev/tty
# passes -e/-r but still fails to open, and a bare `exec` would print a raw bash
# error the caller has already promised to handle quietly.
tty_reattach() {
    [ -e /dev/tty ] && [ -r /dev/tty ] || return 1
    # Probe in a subshell: on a failing `exec <`, the shell writes its own error
    # before any redirection on that same command can suppress it.
    (exec </dev/tty) 2>/dev/null || return 1
    exec </dev/tty
    return 0
}
