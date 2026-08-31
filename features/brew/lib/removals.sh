#!/usr/bin/env bash
# The removal set: every Homebrew item that no ACTIVE Brewfile tier declares.
#
# Shared by mirror.sh (which acts on it) and bump.sh (which only reports it), so
# the two can never disagree about what "untracked" means.

[ -n "${__DOTFILES_BREW_REMOVALS_SH:-}" ] && return 0
__DOTFILES_BREW_REMOVALS_SH=1

# "<kind>\t<name>" (cask | formula | tap) for every Homebrew item no ACTIVE
# Brewfile tier declares — the removal set chez mirror acts on. $1 is the repo
# root; pure/testable. The tier set comes from features/brew/lib/tiers.sh, the
# same resolver chez doctor uses and the mirror of what the brew-bundle hook
# installs from, so "tracked" means the same thing in both directions: a cask
# from a module this Mac has not enabled is untracked here, not silently kept.
# The machine-local overlay is one of those tiers, which is what makes
# `chez adopt --local` stick: a package listed there is declared, so it never
# reaches this set at all.
# `brew bundle cleanup` only honours one --file, so the active tiers are
# concatenated onto stdin (--file=-).
brew_removals() {
    local src=$1

    if [ ! -r "$src/features/brew/lib/tiers.sh" ]; then
        echo "  ! cannot resolve the active Brewfiles: no $src/features/brew/lib/tiers.sh — nothing offered for removal" >&2
        return 1
    fi
    # tiers.sh refuses to load without core/paths.sh, because a resolver that
    # cannot find the machine-local overlay would report every locally adopted
    # package as undeclared — and this function's whole output is the uninstall
    # list. Half-loaded is not usable here.
    if ! . "$src/features/brew/lib/tiers.sh"; then
        echo "  ! cannot load $src/features/brew/lib/tiers.sh — nothing offered for removal" >&2
        return 1
    fi

    # Fail closed: an unresolvable tier set means an empty removal set, never a
    # broader one. Comparing against too FEW tiers would offer the whole
    # toolchain for uninstall.
    local rel abs
    local -a files
    files=()
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        abs="$(brew_resolve_file "$src" "$rel")"
        [ -n "$abs" ] && files+=("$abs")
    done < <(brew_active_files)
    if [ "${#files[@]}" -eq 0 ]; then
        echo "  ! could not resolve the active Brewfiles (is jq installed?) — nothing offered for removal" >&2
        return 1
    fi

    # Homebrew 6.0 refuses to even load a Brewfile referencing an untrusted
    # non-official tap — `brew bundle cleanup` then errors out with nothing on
    # stdout, which used to look identical to "nothing to remove". Trust every
    # declared tap first, same as run_after_02-brew-bundle.sh.tmpl does for installs.
    local taprepo
    while IFS= read -r taprepo; do
        [ -n "$taprepo" ] || continue
        brew trust --tap "$taprepo" >/dev/null 2>&1
    done < <(sed -n 's/^[[:space:]]*tap[[:space:]]*"\([^"]*\)".*/\1/p' "${files[@]}" 2>/dev/null)

    # brew's stderr routinely carries benign noise (API-cache refresh,
    # deprecation notices) even on success, so only surface lines using
    # brew's own convention for a fatal error (`Error: …`) — that's the
    # untrusted-tap failure's exact signature, not a generic "any stderr" check.
    local out err
    err=$(mktemp)
    out=$(cat "${files[@]}" 2>/dev/null |
        brew bundle cleanup --file=- 2>"$err")
    if grep -q '^Error:' "$err" 2>/dev/null; then
        echo "  ! brew bundle cleanup reported errors — removal set may be incomplete:" >&2
        grep '^Error:' "$err" | sed 's/^/      /' >&2
    fi
    rm -f "$err"

    printf '%s\n' "$out" | awk '
            /^Would uninstall casks:/    { kind = "cask";    next }
            /^Would uninstall formulae:/ { kind = "formula"; next }
            /^Would untap:/              { kind = "tap";     next }
            /^Would .brew cleanup.:/     { kind = "";        next }
            /^Run .brew bundle cleanup/  { kind = "";        next }
            kind && NF                   { print kind "\t" $0 }
        '
}

# Remove one package, routing casks/taps to the right subcommand.
brew_uninstall_one() {
    if [ "$1" = cask ]; then
        brew uninstall --cask "$2"
    elif [ "$1" = tap ]; then
        brew untap "$2"
    else
        brew uninstall "$2"
    fi
}
