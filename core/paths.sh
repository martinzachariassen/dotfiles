#!/usr/bin/env bash
# paths.sh — where chez keeps the things that belong to THIS machine.
#
# Two directories, and what separates them is whether losing one costs you
# anything:
#
#   $XDG_CONFIG_HOME/chez   hand-edited, never generated. Back it up.
#   $XDG_STATE_HOME/chez    written by chez for itself. Safe to delete.
#
# Both sit outside the checkout on purpose. A machine-local choice kept inside
# the repo has only two fates: committed, which pushes one Mac's decisions onto
# every other Mac that pulls; or uncommitted, which is permanent `git status`
# noise that eventually gets `git checkout .`-ed away by accident. Outside the
# repo it is neither, and the checkout stays clean.
#
# CHEZ_CONFIG_DIR / CHEZ_STATE_DIR override both, which is how the test suites
# avoid reading the overlay belonging to whoever is running them.

[ -n "${__DOTFILES_PATHS_SH:-}" ] && return 0
__DOTFILES_PATHS_SH=1

# chez_config_dir — machine-local configuration, written by hand.
chez_config_dir() {
    printf '%s\n' "${CHEZ_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/chez}"
}

# chez_state_dir — machine-local state, written by chez.
chez_state_dir() {
    printf '%s\n' "${CHEZ_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/chez}"
}

# chez_local_brewfile — the machine-local Brewfile overlay: the packages THIS
# Mac keeps that the repo does not declare.
#
# It is read as one more Brewfile tier, so a package listed here is *declared*
# in exactly the sense every other package is: `chez doctor` stops calling it
# untracked and `chez mirror` never offers it for uninstall. That is the whole
# mechanism for "this one is mine, on purpose" — and deleting the line puts the
# package straight back on the removal list, which is what makes it reversible.
chez_local_brewfile() {
    printf '%s/Brewfile.local\n' "$(chez_config_dir)"
}
