#!/usr/bin/env bash
# brewfiles.sh — resolve which Brewfile tiers apply to THIS machine.
#
# Shared by chez doctor and the chez mirror / chez status removal set so the install
# and removal directions can't disagree about what "tracked" means. Removal
# used to compare against the `Brewfile.*` glob (every tier that exists), which
# made a work-profile package look tracked on a personal machine and so never
# offered it for uninstall.

[ -n "${__DOTFILES_BREWFILES_SH:-}" ] && return 0

# The machine-local overlay lives outside the checkout, so its path comes from
# core/paths.sh rather than from the data.
#
# A hard dependency, checked before the source guard is set so a second attempt
# is still possible. Degrading to "no overlay" would be the dangerous direction:
# every package adopted with `chez adopt --local` would read as undeclared, and
# the removal verbs would line the lot up for uninstall. Failing to load is the
# only safe reading — the callers all treat a missing brew_active_files as an
# unresolvable tier set and offer nothing.
__brewfiles_paths_sh="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../.." && pwd)/core/paths.sh"
if [ ! -r "$__brewfiles_paths_sh" ]; then
    printf 'tiers.sh: missing %s — this checkout is incomplete\n' "$__brewfiles_paths_sh" >&2
    return 1
fi
__DOTFILES_BREWFILES_SH=1
# shellcheck source=../../../core/paths.sh
. "$__brewfiles_paths_sh"

# brew_active_files [DATA_JSON] — the Brewfile paths that apply here, one per
# line: core, then each enabled module's tier, then this profile's tier — the
# same set, in the same order, that run_after_02-brew-bundle installs from —
# and last, the machine-local overlay if this Mac has one.
#
# Repo tiers come out repo-relative; the overlay comes out ABSOLUTE, because it
# deliberately lives outside the checkout. Resolve either with brew_resolve_file
# rather than by prefixing the repo root.
#
# Reads `chezmoi data` when no JSON is passed. Needs jq; returns 1 without it.
brew_active_files() {
    local json="${1:-}" tiers overlay
    command -v jq >/dev/null 2>&1 || return 1
    [ -n "$json" ] || json="$(chezmoi data --format=json 2>/dev/null)"
    [ -n "$json" ] || return 1
    # `.key as $k` first: inside `select`, the input to `index` is $mods (an
    # array), so a bare `index(.key)` looks up ".key" on the array and errors.
    #
    # Captured rather than streamed so a jq failure stays a FAILURE. Appending
    # the overlay after a bare pipeline would make the function's exit status
    # the overlay's, turning "the data could not be read" into "one tier, and it
    # declares nothing" — which is the reading that offers the whole machine for
    # uninstall. Every fail-closed guard downstream keys off this return.
    tiers="$(printf '%s' "$json" | jq -r '
        (.modules // []) as $mods
        | (.profile // "") as $prof
        | ([.brewfiles.core]
           + ((.brewfiles.byModule // {}) | to_entries
              | map(select(.key as $k | $mods | index($k))) | map(.value))
           + ([(.brewfiles.byProfile // {})[$prof]]))
        | map(select(. != null))
        | .[]' 2>/dev/null)" || return 1

    [ -n "$tiers" ] && printf '%s\n' "$tiers"
    # Last, so it can only ever ADD to the declared set — never reorder a repo
    # tier, and never shadow one.
    overlay="$(chez_local_brewfile)"
    [ -f "$overlay" ] && printf '%s\n' "$overlay"
    return 0
}

# brew_seed_local_brewfile SRC — create the overlay from the shipped template
# when this Mac has none. A hatch nobody knows about is not a hatch, so the file
# is written on the first apply rather than the first time someone needs it: an
# empty, commented Brewfile.local sitting in ~/.config/chez explains itself, and
# a mechanism documented only in the repo does not.
#
# The one function here that writes. It lives beside the resolver because the
# overlay's path, its contents and its reader are one idea and were duplicated
# across chez adopt and the apply hook before this; chez doctor sources this
# file and never calls it, so doctor stays read-only.
#
# An existing overlay is an untouched no-op. Returns 1 only if it could not be
# created.
brew_seed_local_brewfile() {
    local file template
    file="$(chez_local_brewfile)"
    [ -f "$file" ] && return 0
    mkdir -p "$(dirname "$file")" || return 1
    template="$1/features/brew/Brewfile.local.template"
    if [ -f "$template" ]; then
        cp "$template" "$file"
    else
        printf '# Brewfile.local — packages this Mac keeps that the repo does not declare.\n' >"$file"
    fi
}

# brew_resolve_file SRC PATH — PATH as an existing absolute file, or nothing.
#
# The one place that knows a repo tier is repo-relative and the overlay is not,
# so no caller has to special-case it and none can get the rule half-right.
brew_resolve_file() {
    case "$2" in
        /*) [ -f "$2" ] && printf '%s\n' "$2" ;;
        *) [ -f "$1/$2" ] && printf '%s\n' "$1/$2" ;;
    esac
    return 0
}

# brew_bare_names — stdin → sorted, deduped, bare formula names on stdout.
#
# The comparison key for "is this install declared anywhere?", and it must be
# applied to BOTH sides or nothing tap-installed ever matches. `brew leaves`
# prints a tap-qualified name for anything outside homebrew/core
# (hashicorp/tap/terraform), while a Brewfile may declare the same formula
# either way — and tap owners carry capitals that the installed name does not
# (`brew "Azure/kubelogin/kubelogin"` installs as azure/kubelogin/kubelogin).
# So: last path component, lowercased. Normalising only the Brewfile side is
# exactly the bug this replaces — every tap formula read as untracked forever.
brew_bare_names() {
    awk -F/ 'NF { print tolower($NF) }' | sort -u
}

# brew_untracked_of_kind KIND INSTALLED FILE… — the installed items of KIND
# (`brew` or `cask`) that none of the given Brewfiles declare, one bare name
# per line.
#
# KIND is a parameter rather than the two sets being folded together on
# purpose. Formulae and casks are separate Homebrew namespaces and some names
# exist in both — docker ships as a formula *and* as a cask — so a merged
# comparison lets a declared cask vouch for an undeclared formula of the same
# name. Comparing within one kind cannot make that mistake.
#
# Both sides go through brew_bare_names so the tap-qualification and casing of
# each is irrelevant; see that function for why that symmetry matters.
brew_untracked_of_kind() {
    local kind=$1 installed=$2
    shift 2
    # `grep -h PATTERN` with zero file operands reads stdin and would hang the
    # caller forever, so an empty tier set is refused rather than compared
    # against.
    [ "$#" -gt 0 ] || return 1
    comm -23 \
        <(printf '%s\n' "$installed" | brew_bare_names) \
        <(grep -h "^${kind} " "$@" 2>/dev/null |
            sed -E "s/^${kind} \"([^\"]+)\".*/\1/" |
            brew_bare_names)
}
