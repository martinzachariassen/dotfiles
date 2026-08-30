#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_check_fonts() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# Not owned by a feature: the Nerd Font is what makes the prompt, the status
# line and half the CLI output legible, and it is installed by a cask that any
# profile may or may not carry.

doctor_check_fonts() {
    section "Fonts"
    # Glob install locations directly (`ls | grep` mangles non-alphanumeric names).
    jetbrains_nerd_font_installed() {
        local f
        for f in "$HOME/Library/Fonts"/JetBrainsMono*Nerd* \
            /Library/Fonts/JetBrainsMono*Nerd* \
            /opt/homebrew/Caskroom/font-jetbrains-mono-nerd-font/*; do
            [ -e "$f" ] && return 0
        done
        return 1
    }
    if jetbrains_nerd_font_installed; then
        pass "JetBrainsMono Nerd Font installed"
    else
        warn "JetBrainsMono Nerd Font not found — terminal icons will look broken"
    fi
}
