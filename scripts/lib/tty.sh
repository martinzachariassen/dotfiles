#!/usr/bin/env bash
# tty.sh — reattach a chezmoi hook's stdin to the controlling terminal.
# chezmoi runs run_* scripts with stdin closed, so interactive steps (sudo, y/N
# prompts) need stdin pointed back at /dev/tty first.
# shellcheck disable=SC2329

[ -n "${__DOTFILES_TTY_SH:-}" ] && return 0
__DOTFILES_TTY_SH=1

# Return 0 and point stdin at /dev/tty if readable; else return 1 (caller decides).
tty_reattach() {
    if [ -e /dev/tty ] && [ -r /dev/tty ]; then
        exec </dev/tty
        return 0
    fi
    return 1
}
