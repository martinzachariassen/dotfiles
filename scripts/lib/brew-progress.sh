#!/usr/bin/env bash
# brew-progress.sh — turn `brew bundle install` output into real progress.
#
# The denominator is genuine, not decorative. Homebrew's installer prints exactly
# one line per Brewfile entry (Library/Homebrew/bundle/installer.rb):
#
#     puts Formatter.success("#{verb} #{name}")   # verb: Installing/Upgrading/Tapping
#     puts "Using #{name}" unless quiet           # already present
#
# So: total = declared entries, and each such line is one entry actually
# resolved. Nothing here interpolates or animates on a timer.
# shellcheck disable=SC2034,SC2329

[ -n "${__DOTFILES_BREW_PROGRESS_SH:-}" ] && return 0
__DOTFILES_BREW_PROGRESS_SH=1

# brew_pkg_count FILE — entries a Brewfile declares (formulae, casks, App Store
# apps, taps, VS Code extensions). Matches what the installer will iterate.
# `grep -c` prints "0" AND exits 1 when nothing matches, so a `|| echo 0` fallback
# emits the count twice — which turns $((total + $(brew_pkg_count f))) into a
# syntax error. Guard on the value, not the exit status.
brew_pkg_count() {
    local n
    n="$(grep -cE '^[[:space:]]*(brew|cask|mas|tap|vscode)[[:space:]]' "$1" 2>/dev/null || true)"
    case "$n" in
        '' | *[!0-9]*) n=0 ;;
    esac
    printf '%s\n' "$n"
}

# brew_entry_name LINE — the entry a status line refers to, ANSI stripped.
# "Using jq" → jq · "✔ Installing ripgrep" → ripgrep · "✔ Tapping a/b" → a/b
# -E (ERE) is required: macOS ships BSD sed, where `\|` alternation is a GNU
# extension and silently matches a literal pipe instead.
brew_entry_name() {
    printf '%s\n' "$1" |
        sed -E -e "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g" \
            -e 's/.*(Using|Installing|Upgrading|Tapping) //' \
            -e 's/[ .].*//'
}

# brew_fetch_label LINE — what to show during a download. "Fetching <pkg>" names
# the package; a bare URL download does not, so say only that rather than
# printing a URL fragment or a sha256 as if it were a package name.
brew_fetch_label() {
    local rest
    rest="$(printf '%s\n' "$1" |
        sed -E -e "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g" \
            -e 's/.*(Fetching|Downloading) //')"
    case "$rest" in
        http* | "") printf 'downloading' ;;
        *) printf 'fetching %s' "$(printf '%s' "$rest" | sed -E 's/ .*//')" ;;
    esac
}

# brew_progress_consume SENTINEL — read brew output on stdin, ticking the shared
# ui_progress counter once per resolved entry. Returns when SENTINEL arrives.
#
# The sentinel exists because macOS ships bash 3.2, where `read -t` returns 1 for
# BOTH a timeout and real EOF (the >128 convention is bash 4+). Without it the
# loop cannot tell "still downloading" from "finished", and either exits early or
# hangs. The 1s timeout is what keeps the clock moving during a long single
# download, when no new line arrives for minutes.
brew_progress_consume() {
    local sentinel="$1" line current="" idle=0 max_idle="${BREW_PROGRESS_MAX_IDLE:-3600}"
    while :; do
        if IFS= read -r -t 1 line; then
            idle=0
            [ "$line" = "$sentinel" ] && break
            case "$line" in
                *"Using "* | *"Installing "* | *"Upgrading "* | *"Tapping "*)
                    current="$(brew_entry_name "$line")"
                    ui_progress_tick "$current"
                    ;;
                *"==> Fetching"* | *"==> Downloading"*)
                    # Homebrew bulk-fetches before resolving any entry; show that
                    # rather than sitting at 0/N with no explanation.
                    ui_progress_render "$(brew_fetch_label "$line")"
                    ;;
            esac
        else
            # Timeout or EOF — indistinguishable on bash 3.2. Redraw so elapsed
            # advances; the sentinel ends the loop, and this cap only catches a
            # producer killed mid-stream.
            idle=$((idle + 1))
            [ "$idle" -gt "$max_idle" ] && break
            ui_progress_render "$current"
        fi
    done
}
