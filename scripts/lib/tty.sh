#!/usr/bin/env bash
# tty.sh — reattach a chezmoi hook's stdin to the controlling terminal.
#
# chezmoi runs run_* scripts with stdin closed, so any interactive step (a sudo
# password, a y/N prompt) needs stdin pointed back at /dev/tty first. Several
# hooks did the same `[ -e /dev/tty ] && [ -r /dev/tty ] && exec </dev/tty`
# dance with slightly different wording; this centralises the detection. It is
# sourced at RUNTIME by the hooks (they can source — unlike install.sh — because
# the repo already exists on disk by the time a hook runs).
#
# tty_reattach: if a readable controlling terminal exists, point this shell's
# stdin at it and return 0; otherwise leave stdin as-is and return 1 so the
# caller can print its own no-TTY message and skip or continue as it sees fit.
#
# Consumed by sourcing callers, so tty_reattach reads as unreachable here.
# shellcheck disable=SC2329

[ -n "${__DOTFILES_TTY_SH:-}" ] && return 0
__DOTFILES_TTY_SH=1

tty_reattach() {
    if [ -e /dev/tty ] && [ -r /dev/tty ]; then
        exec </dev/tty
        return 0
    fi
    return 1
}
