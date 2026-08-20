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

# brew_strip_ansi LINE — the line with colour escapes and any leading status
# glyph removed, so the matchers below can anchor on the first real word.
# -E (ERE) is required: macOS ships BSD sed, where `\|` alternation is a GNU
# extension and silently matches a literal pipe instead.
brew_strip_ansi() {
    printf '%s\n' "$1" |
        sed -E -e "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g" \
            -e 's/^[^A-Za-z=]*//'
}

# brew_is_entry_line CLEAN — 0 when CLEAN is `brew bundle`'s own one-per-entry
# status line, which is the only thing the denominator counts.
#
# Anchored deliberately. Homebrew narrates its *internal* work with the same
# verbs — "==> Installing dependencies for xcodes: openssl@3", "==> Installing
# xcodes dependency: openssl@3" — and a substring match ticked once per
# transitive dependency, which is how a 65-package run reported 66/65 at 101%.
# Bundle's lines (Library/Homebrew/bundle/installer.rb) are printed bare, so
# "starts with the verb" separates them from "==> " chatter exactly.
brew_is_entry_line() {
    case "$1" in
        "Using "* | "Installing "* | "Upgrading "* | "Tapping "*) return 0 ;;
        *) return 1 ;;
    esac
}

# brew_entry_name CLEAN — the entry an already-matched status line refers to.
# "Using jq" → jq · "Installing ripgrep" → ripgrep · "Tapping a/b" → a/b
brew_entry_name() {
    printf '%s\n' "$1" |
        sed -E -e "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g" \
            -e 's/^[^A-Za-z]*//' \
            -e 's/^(Using|Installing|Upgrading|Tapping) //' \
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
#
# BREW_PROGRESS_STALL is the other half of that timeout. After this many silent
# seconds the bar is *parked*: cleared once, explained, and then not repainted
# until Homebrew speaks again. Casks write `sudo` prompts straight to /dev/tty,
# which a 1Hz `\r\033[K` redraw erases — so a machine waiting for a password
# looked identical to one downloading, and the install sat there until the
# prompt timed out. Parking costs a frozen elapsed clock during long downloads;
# an erased password prompt costs the package.
brew_progress_consume() {
    local sentinel="$1" line clean current="" idle=0 parked=0
    local max_idle="${BREW_PROGRESS_MAX_IDLE:-3600}"
    local stall="${BREW_PROGRESS_STALL:-90}"
    while :; do
        if IFS= read -r -t 1 line; then
            idle=0
            [ "$line" = "$sentinel" ] && break
            # Coming back from a park: the note stays, the bar resumes below it.
            parked=0
            clean="$(brew_strip_ansi "$line")"
            case "$clean" in
                "==> Fetching"* | "==> Downloading"*)
                    # Homebrew bulk-fetches before resolving any entry; show that
                    # rather than sitting at 0/N with no explanation.
                    ui_progress_render "$(brew_fetch_label "$clean")"
                    ;;
                "==>"*) ;; # Homebrew's own narration — never a bundle entry.
                *)
                    if brew_is_entry_line "$clean"; then
                        current="$(brew_entry_name "$clean")"
                        ui_progress_tick "$current"
                    fi
                    ;;
            esac
        else
            # Timeout or EOF — indistinguishable on bash 3.2. The sentinel ends
            # the loop; this cap only catches a producer killed mid-stream.
            idle=$((idle + 1))
            [ "$idle" -gt "$max_idle" ] && break
            if [ "$idle" -eq "$stall" ]; then
                parked=1
                ui_progress_pause "$(brew_stall_note "$current" "$stall")"
            elif [ "$parked" -eq 0 ]; then
                ui_progress_render "$current"
            fi
        fi
    done
}

# brew_stall_note ITEM SECONDS — what to leave on screen when the bar parks.
# Deliberately does not claim a password is being asked for: a big cask download
# is silent for the same reason. It names both possibilities and gets out of the
# way so whichever one it is can show itself.
brew_stall_note() {
    local item="${1:-}" secs="${2:-90}"
    if [ -n "$item" ]; then
        printf 'no output from Homebrew for %ss on "%s" — it is on a long download, or waiting for a password prompt below.' "$secs" "$item"
    else
        printf 'no output from Homebrew for %ss — it is on a long download, or waiting for a password prompt below.' "$secs"
    fi
}
