#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_check_xdg() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# The XDG layout every other config in this repo is addressed against. A stray
# ~/.zshrc or ~/.gitconfig silently outranks the managed copy.

doctor_check_xdg() {
    section "XDG layout"
    for legacy in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.gitconfig" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile"; do
        if [ -f "$legacy" ]; then
            fail "legacy $legacy present — would shadow XDG-managed config. Run \`chez apply\` to remove."
        else
            pass "no legacy $(basename "$legacy")"
        fi
    done
    if [ -f "$HOME/.config/zsh/.zshrc" ]; then
        pass "~/.config/zsh/.zshrc present"
    else
        fail "~/.config/zsh/.zshrc missing — run: chezmoi apply"
    fi
    # .zshenv must stay in $HOME (zsh reads it before ZDOTDIR is set)
    if [ -f "$HOME/.zshenv" ]; then
        pass "~/.zshenv present (must stay in \$HOME)"
    else
        fail "~/.zshenv missing — run: chezmoi apply"
    fi
}
