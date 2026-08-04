#!/usr/bin/env bash
# homebrew.sh — shared Homebrew installer, used by the once-before chezmoi
# hook. install.sh keeps its own inline copy of this same install step: it
# runs before the repo is cloned, so it can't source anything here yet.
# shellcheck disable=SC2329

[ -n "${__DOTFILES_HOMEBREW_SH:-}" ] && return 0
__DOTFILES_HOMEBREW_SH=1

# homebrew_install — install Homebrew if `brew` isn't already on PATH, and
# put it on PATH for the rest of this process. Idempotent: a no-op when brew
# is already present.
homebrew_install() {
    command -v brew >/dev/null 2>&1 && return 0

    local installer
    installer="$(mktemp)"
    trap 'rm -f "$installer"' RETURN
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"
    NONINTERACTIVE=1 /bin/bash "$installer"

    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
}
