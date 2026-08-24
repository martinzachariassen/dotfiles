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

# ── Password prompts during an install ────────────────────────────────────────
#
# Casks that ship an Apple installer package run it under `sudo`. Homebrew hands
# that child a closed pipe for stdin (Library/Homebrew/system_command.rb), so
# sudo cannot read stdin and falls back to opening /dev/tty itself. Its prompt
# therefore never enters the pipeline this file reads — it lands straight on the
# terminal, underneath the progress bar, and the next `\r\033[K` redraw erases
# it. What the user sees is a bar frozen at the same count with no explanation,
# while sudo silently counts down `passwd_timeout` and then fails the cask. That
# is the "sometimes it works" behaviour: it worked whenever someone happened to
# type blind into an invisible prompt before it expired.
#
# The fix is not to guess from silence — a 500 MB download is silent for exactly
# the same reason, which is why the old 90-second stall heuristic could never be
# more than a hedge. It is to ask sudo directly. `sudo -n true` succeeds only
# when a call would NOT prompt, so:
#
#   ticket held    → nothing can prompt → keep the bar live, clock and all
#   ticket missing → a prompt may arrive at any moment → stop drawing entirely,
#                    say what is about to be asked, and leave the line free
#
# Polling also refreshes the timestamp, so in the normal case (pre-authorised by
# the hook before the bar ever starts) the ticket cannot lapse mid-run and the
# bar never has to park at all.

# brew_sudo_ready — 0 when Homebrew cannot be blocked on a password prompt.
#
# `-n` never prompts, so this is safe to poll from inside the render loop. stdin
# is /dev/null deliberately: the loop's own stdin is the pipe carrying brew's
# output, and sudo must not eat a line of it. No sudo on PATH means nothing can
# prompt. BREW_PROGRESS_SUDO_PROBE=0 disables the probe for non-interactive runs.
brew_sudo_ready() {
    [ "${BREW_PROGRESS_SUDO_PROBE:-1}" = "1" ] || return 0
    command -v sudo >/dev/null 2>&1 || return 0
    sudo -n true </dev/null >/dev/null 2>&1
}

# brew_is_sudo_notice CLEAN — 0 when CLEAN is Homebrew announcing that it is
# about to run something under sudo. Current Homebrew prints
#   ==> Running installer for docker-desktop with `sudo` (which may request your password)...
# and older versions ended it "; the password may be necessary." Matching any of
# the three lets the bar park on the exact line before the prompt, rather than
# waiting for the poll interval to notice.
brew_is_sudo_notice() {
    case "$1" in
        *'may request your password'* | *'password may be necessary'* | *'with `sudo`'*) return 0 ;;
        *) return 1 ;;
    esac
}

# brew_sudo_notice_target LINE [FALLBACK] — the cask an already-matched sudo
# notice refers to, so the banner can name what is being installed. Falls back
# to the caller's current entry when the wording changes upstream.
brew_sudo_notice_target() {
    local name
    name="$(printf '%s\n' "$1" | sed -nE 's/.*installer for ([^ ]+).*/\1/p')"
    if [ -n "$name" ]; then
        printf '%s' "$name"
    else
        printf '%s' "${2:-}"
    fi
}

# brew_sudo_park ITEM — clear the bar and explain the prompt that is coming.
#
# `dim`, not `explain`: QUIET=1 drops prose, and the one thing that must never
# arrive unannounced is a password prompt. Several short lines on purpose — this
# is the single moment in an otherwise unattended install where the machine
# needs a human, and it has to be readable at a glance.
brew_sudo_park() {
    local item="${1:-}"
    ui_progress_pause ""
    hr
    printf '%s  %s%s%s %s%s%s\n' "$(line_prefix)" "$YELLOW" "$NODE" "$RESET" \
        "$BOLD" "Administrator password needed" "$RESET"
    # "around" and not "installing": the last entry line we saw is a good hint at
    # who is asking, but Homebrew can start the installer for one cask while the
    # counter still reads the previous one. brew_sudo_park_target names it exactly
    # once Homebrew says so — that correction must not read as a contradiction.
    if [ -n "$item" ]; then
        dim "Homebrew is around \"$item\" and has reached a step that installs"
        dim "with an Apple installer package. macOS will not run it without admin."
    else
        dim "Homebrew has reached a step that needs admin access."
    fi
    dim "Type your macOS login password at the prompt below, then press Enter."
    dim "Nothing appears as you type — that is normal, not a frozen terminal."
    dim "Touch ID works here too, if you have it enabled for sudo."
    dim "The install is paused until you answer; the progress bar is hidden so"
    dim "nothing overwrites the prompt."
    hr
}

# brew_sudo_park_target ITEM — name the cask once the bar is already parked.
#
# Order of events on a machine that never had a ticket: the bar parks before the
# first line of output, so the banner cannot say what is being installed —
# Homebrew only names the cask on the line immediately before it calls sudo.
# This adds that name when it arrives, rather than leaving the user to guess
# which of sixty-five packages stopped the install.
brew_sudo_park_target() {
    printf '%s  %s%s%s It is %s"%s"%s asking — the prompt is below.\n' \
        "$(line_prefix)" "$YELLOW" "$NODE" "$RESET" "$BOLD" "$1" "$RESET"
}

# brew_sudo_unpark — confirm what happened, before the bar comes back.
# The ticket is re-checked rather than assumed: a prompt can also end by timing
# out or being declined, and reporting that as success is worse than not
# reporting it at all.
brew_sudo_unpark() {
    if brew_sudo_ready; then
        ok "password accepted — resuming the install"
    else
        warn "continuing without admin access — apps that need an installer may fail"
    fi
}

# brew_parked_line ITEM — a settled "[12/65] docker-desktop" line, used in place
# of the bar while parked. Printed only when an entry genuinely finishes, so it
# can never appear while a prompt is on screen waiting (Homebrew is blocked, and
# blocked means no output) — but a run that continued past a declined prompt
# still visibly makes progress instead of looking dead.
brew_parked_line() {
    dim "$(printf '[%s/%s] %s' "$(ui_progress_count)" "${UI_PROGRESS_TOTAL:-0}" "${1:-}")"
}

# brew_quiet_label ITEM SECS — the bar's label once Homebrew has gone quiet.
# Reached only while the ticket is held, which rules a prompt out — so this can
# say plainly that it is a download and keep the elapsed clock running, instead
# of parking and freezing it for the several minutes a big cask takes.
brew_quiet_label() {
    local item="${1:-}" secs="${2:-0}" for_
    for_="$(printf '%dm%02ds' "$((secs / 60))" "$((secs % 60))")"
    if [ -n "$item" ]; then
        printf '%s — quiet for %s, still downloading' "$item" "$for_"
    else
        printf 'quiet for %s, still downloading' "$for_"
    fi
}

# brew_progress_consume SENTINEL — read brew output on stdin, ticking the shared
# ui_progress counter once per resolved entry. Returns when SENTINEL arrives.
#
# The sentinel exists because macOS ships bash 3.2, where `read -t` returns 1 for
# BOTH a timeout and real EOF (the >128 convention is bash 4+). Without it the
# loop cannot tell "still downloading" from "finished", and either exits early or
# hangs. The 1s timeout is what keeps the clock moving during a long single
# download, when no new line arrives for minutes — and what paces the sudo poll.
brew_progress_consume() {
    local sentinel="$1" line clean label current="" named="" ticked
    local idle=0 parked=0 since_poll=0
    local max_idle="${BREW_PROGRESS_MAX_IDLE:-3600}"
    local quiet_after="${BREW_PROGRESS_STALL:-90}"
    local poll="${BREW_SUDO_POLL:-15}"

    # Settle the ticket question before drawing anything at all. A bar that
    # never appears is better than one that appears and then eats a prompt.
    if ! brew_sudo_ready; then
        parked=1
        brew_sudo_park ""
    fi

    while :; do
        label=""
        ticked=0
        if IFS= read -r -t 1 line; then
            idle=0
            [ "$line" = "$sentinel" ] && break
            clean="$(brew_strip_ansi "$line")"
            case "$clean" in
                "==> Fetching"* | "==> Downloading"*)
                    # Homebrew bulk-fetches before resolving any entry; show that
                    # rather than sitting at 0/N with no explanation.
                    label="$(brew_fetch_label "$clean")"
                    ;;
                "==>"*)
                    # Homebrew's own narration — never a bundle entry, but it is
                    # where sudo gets announced. Force the poll on that line so
                    # the bar is already out of the way when sudo speaks.
                    if brew_is_sudo_notice "$clean"; then
                        current="$(brew_sudo_notice_target "$clean" "$current")"
                        if [ "$parked" -eq 1 ]; then
                            if [ -n "$current" ] && [ "$current" != "$named" ]; then
                                named="$current"
                                brew_sudo_park_target "$current"
                            fi
                        else
                            since_poll="$poll"
                        fi
                    fi
                    label="$current"
                    ;;
                *)
                    if brew_is_entry_line "$clean"; then
                        current="$(brew_entry_name "$clean")"
                        ui_progress_advance
                        ticked=1
                    fi
                    label="$current"
                    ;;
            esac
        else
            # Timeout or EOF — indistinguishable on bash 3.2. The sentinel ends
            # the loop; this cap only catches a producer killed mid-stream.
            idle=$((idle + 1))
            [ "$idle" -gt "$max_idle" ] && break
            label="$current"
            [ "$idle" -ge "$quiet_after" ] && label="$(brew_quiet_label "$current" "$idle")"
        fi

        since_poll=$((since_poll + 1))
        if [ "$since_poll" -ge "$poll" ]; then
            since_poll=0
            if brew_sudo_ready; then
                if [ "$parked" -eq 1 ]; then
                    parked=0
                    brew_sudo_unpark
                fi
            elif [ "$parked" -eq 0 ]; then
                parked=1
                named="$current"
                brew_sudo_park "$current"
            fi
        fi

        if [ "$parked" -eq 1 ]; then
            [ "$ticked" -eq 1 ] && brew_parked_line "$current"
        else
            ui_progress_render "$label"
        fi
    done
}

# ── Failure reporting ─────────────────────────────────────────────────────────
# When a Brewfile fails, the output that would explain why has already been
# consumed to drive the bar. These two turn the captured log and Homebrew's own
# state back into an answer, instead of a blind `tail` that shows the last few
# successes and none of the error.

# brew_unmet_entries FILE — the entries FILE still declares but the machine
# lacks, one "Cask docker-desktop" / "Formula a/b/c" per line.
#
# Two macOS traps in one command: `brew bundle check` reports on **stderr**, and
# `sed -E` is required because BSD sed reads `\|` as a literal pipe rather than
# alternation, which silently matches nothing.
brew_unmet_entries() {
    brew bundle check --verbose --no-upgrade --file="$1" 2>&1 |
        sed -nE 's/^[^A-Za-z]*((Cask|Formula|Tap|VSCode|App) .*) needs to be installed\.?/\1/p'
}

# brew_error_lines LOG [MAX] — the lines from LOG that state a failure, newest
# last. Falls back to the tail only when nothing matches, so there is always
# something to read.
# brew_sudo_failed LOG — 0 when LOG shows sudo itself giving up: the prompt
# timed out, was declined, or was never answerable. Worth separating from a
# failed download, because the advice is the opposite — a retry of the same
# download may well work, whereas this one only stops happening if the password
# is given (or pre-authorised) next time.
brew_sudo_failed() {
    grep -aqiE 'sudo: (a (terminal|password)|no (tty|password|askpass)|[0-9]+ incorrect|timed out reading password)' \
        "$1" 2>/dev/null
}

brew_error_lines() {
    local log="$1" max="${2:-12}" hits
    # `^sudo:` too: a prompt that timed out is the failure, but it says neither
    # "error" nor "fatal", so the old pattern reported a dead download instead.
    hits="$(grep -aiE '^[^A-Za-z]*(error|fatal|warning: .*fail)|^sudo:' "$log" 2>/dev/null | tail -n "$max")"
    if [ -n "$hits" ]; then
        printf '%s\n' "$hits"
    else
        tail -n "$max" "$log" 2>/dev/null || true
    fi
    # Reporting helper: an unreadable log is worth saying nothing about, never
    # worth failing an apply over.
    return 0
}
