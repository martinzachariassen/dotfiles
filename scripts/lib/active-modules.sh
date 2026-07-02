#!/usr/bin/env bash
# active-modules.sh — resolve which Brewfile modules apply to a given profile +
# feature set. One mapping, so "which Brewfiles are active" is answered the same
# way by the installer, the health check, and any future consumer.
#
# The core Brewfile is always active; the mac-apps module is gated by the macApps
# feature; the profile module (personal/work) is gated by the profile. This
# mirrors the module selection the brew-bundle hook performs at render time via
# Go-template conditionals (that hook stays templated — it needs the values at
# render time — but the ordering here is kept identical to it on purpose).
#
# Consumed by sourcing callers (doctor.sh) and by inlining (install.sh embeds the
# @inline region; it can't source — see scripts/build-install.sh).
# shellcheck disable=SC2034,SC2329

# Source guard kept OUTSIDE the @inline region (see chezmoi-data.sh for why).
[ -n "${__DOTFILES_ACTIVE_MODULES_SH:-}" ] && return 0
__DOTFILES_ACTIVE_MODULES_SH=1

# @inline-begin
# active_modules PROFILE MACAPPS [BASEDIR]
# Print the active Brewfile module paths, one per line, in install order. When
# BASEDIR is given, each path is prefixed with "BASEDIR/" (absolute paths for
# `brew bundle`); otherwise repo-relative paths are printed.
active_modules() {
    local profile="${1:-personal}" macapps="${2:-true}" base="${3:-}" prefix=""
    [ -n "$base" ] && prefix="$base/"

    printf '%s%s\n' "$prefix" "Brewfile"
    case "$macapps" in
        true | 1 | yes) printf '%s%s\n' "$prefix" "brewfiles/Brewfile.mac-apps" ;;
    esac
    case "$profile" in
        personal) printf '%s%s\n' "$prefix" "brewfiles/Brewfile.personal" ;;
        work) printf '%s%s\n' "$prefix" "brewfiles/Brewfile.work" ;;
    esac
}
# @inline-end
