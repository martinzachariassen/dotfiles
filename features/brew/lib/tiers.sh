#!/usr/bin/env bash
# brewfiles.sh — resolve which Brewfile tiers apply to THIS machine.
#
# Shared by chez doctor and the chez mirror / chez status removal set so the install
# and removal directions can't disagree about what "tracked" means. Removal
# used to compare against the `Brewfile.*` glob (every tier that exists), which
# made a work-profile package look tracked on a personal machine and so never
# offered it for uninstall.

[ -n "${__DOTFILES_BREWFILES_SH:-}" ] && return 0
__DOTFILES_BREWFILES_SH=1

# brew_active_files [DATA_JSON] — repo-relative Brewfile paths, one per line:
# core, then each enabled module's tier, then this profile's tier — the same
# set, in the same order, that run_after_02-brew-bundle installs from.
# Reads `chezmoi data` when no JSON is passed. Needs jq; returns 1 without it.
brew_active_files() {
    local json="${1:-}"
    command -v jq >/dev/null 2>&1 || return 1
    [ -n "$json" ] || json="$(chezmoi data --format=json 2>/dev/null)"
    [ -n "$json" ] || return 1
    # `.key as $k` first: inside `select`, the input to `index` is $mods (an
    # array), so a bare `index(.key)` looks up ".key" on the array and errors.
    printf '%s' "$json" | jq -r '
        (.modules // []) as $mods
        | (.profile // "") as $prof
        | ([.brewfiles.core]
           + ((.brewfiles.byModule // {}) | to_entries
              | map(select(.key as $k | $mods | index($k))) | map(.value))
           + ([(.brewfiles.byProfile // {})[$prof]]))
        | map(select(. != null))
        | .[]' 2>/dev/null
}
