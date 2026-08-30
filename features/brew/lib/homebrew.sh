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

# ── Third-party tap trust ─────────────────────────────────────────────────────
# Homebrew 6.0 refuses to load formulae and casks from non-official taps until
# the tap is trusted, and `brew bundle` skips the untrusted ones *silently* —
# which is how a work-profile install finished "successfully" with no kubelogin
# and no terraform.
#
# Shared by the brew-bundle hook (which grants trust) and chezdoctor (which
# reports on it) so the two can't disagree about which taps this machine needs.

# brew_trust_store — pin the file Homebrew records trust in, and echo its path.
#
# Homebrew writes $XDG_CONFIG_HOME/homebrew/trust.json when that variable is set
# and ~/.homebrew/trust.json when it isn't. install.sh runs under `curl | bash`
# with XDG_CONFIG_HOME unset, while the zshenv it deploys always sets it — so a
# first install granted trust in one file and every later shell read the other,
# leaving two half-populated stores and taps that looked untrusted again.
brew_trust_store() {
    export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    printf '%s\n' "$XDG_CONFIG_HOME/homebrew/trust.json"
}

# brew_declared_taps FILE... — every non-official tap the FILEs depend on,
# lowercased (Homebrew normalises "Azure/kubelogin" to "azure/kubelogin") and
# deduped. Both spellings count: an explicit `tap "org/name"` line, and the tap
# implied by a fully-qualified `brew "org/name/formula"` entry — a Brewfile can
# use the latter without the former.
brew_declared_taps() {
    local f
    for f in "$@"; do
        [ -f "$f" ] || continue
        # `#` as the delimiter, not `/` or `|`: the second pattern needs both a
        # literal slash and ERE alternation, and escaping either against its own
        # delimiter makes BSD sed read it as a literal character instead.
        sed -nE \
            -e 's#^[[:space:]]*tap[[:space:]]*"([^"]+)".*#\1#p' \
            -e 's#^[[:space:]]*(brew|cask)[[:space:]]*"([^"/]+/[^"/]+)/[^"]+".*#\2#p' \
            "$f"
    done | tr '[:upper:]' '[:lower:]' | sort -u
}

# brew_trusted_taps — the taps Homebrew currently trusts, one per line.
#
# Parsed out of `brew trust --json v1` with sed rather than jq on purpose: the
# first caller is the hook that installs jq, so jq isn't on PATH yet. The `/
# "taps"/d` drops the array's own header line, which the value matcher would
# otherwise capture as a tap named "taps".
brew_trusted_taps() {
    brew trust --json v1 2>/dev/null |
        sed -n '/"taps"[[:space:]]*:[[:space:]]*\[/,/\]/{ /"taps"/d; s/^[[:space:]]*"\([^"]*\)".*/\1/p; }' |
        tr '[:upper:]' '[:lower:]' | sort -u
}

# brew_untrusted_taps FILE... — the declared taps Homebrew does not trust yet,
# one per line. Empty output means nothing will be silently skipped.
brew_untrusted_taps() {
    local declared
    declared="$(brew_declared_taps "$@")"
    [ -n "$declared" ] || return 0
    comm -23 <(printf '%s\n' "$declared") <(brew_trusted_taps)
}

# brew_trust_taps FILE... — trust every tap the FILEs declare, then re-read
# Homebrew's own store and print the ones that did not take.
#
# Verifying afterwards is the point. The previous version keyed off `brew
# trust`'s exit status, which reports "asked politely", not "recorded" — a
# store written somewhere the next command wouldn't look still exited 0.
brew_trust_taps() {
    local t
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        brew trust --tap "$t" >/dev/null 2>&1 || true
    done <<EOF
$(brew_untrusted_taps "$@")
EOF
    brew_untrusted_taps "$@"
}
