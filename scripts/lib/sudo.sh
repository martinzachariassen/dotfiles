#!/usr/bin/env bash
# sudo.sh — background sudo-timestamp keeper shared by run_before_00-sudo-cache
# and macos-defaults.sh. An apply (or a defaults pass) can run past sudo's
# default 5-min cache; this refreshes it (sudo -n, never prompts/Touch ID)
# until the watched process exits.
# shellcheck disable=SC2329

[ -n "${__DOTFILES_SUDO_SH:-}" ] && return 0
__DOTFILES_SUDO_SH=1

# sudo_keep_warm PID [REFRESH_SECS] — double-forked so the caller's shell
# doesn't wait on the process group; polls every 2s to notice PID exiting
# promptly, refreshing sudo every REFRESH_SECS of *wall clock* (default 120,
# comfortably inside sudo's 5-minute cache).
#
# Wall clock, not a countdown, because the countdown drifted. It decremented a
# counter by 2 per `sleep 2` iteration and refreshed after 120 of them — but an
# iteration also forks `kill -0` and does arithmetic, so under the I/O load of a
# 65-package `brew bundle` each one costs more than 2s. At a 2.5s average, the
# "240s" refresh actually fired at 300s: precisely when the ticket had already
# expired. That is how an apply that pre-authorised sudo still hit a password
# prompt at the macOS-defaults step minutes later.
#
# The default also drops from 240 to 120. A no-op `sudo -n true` every two
# minutes costs nothing, and it leaves margin for a machine that sleeps or
# stalls rather than assuming the loop is punctual.
#
# A refresh that fails does not end the keeper. It used to: `sudo -n true ||
# exit` gave up permanently on the first miss, so one transient failure early in
# a 13-minute `brew bundle` left every later step (macOS defaults) to prompt
# again — after the apply had already promised the password was only needed
# once. Only a run of consecutive failures means the ticket is genuinely gone,
# at which point there is nothing left to keep warm and the later steps prompt
# for themselves.
sudo_keep_warm() {
    local watch_pid="$1" refresh_secs="${2:-120}"
    local max_misses="${SUDO_KEEP_WARM_MAX_MISSES:-3}"
    (
        (
            local next=0 misses=0 now
            while kill -0 "$watch_pid" 2>/dev/null; do
                now="$(date +%s 2>/dev/null || echo 0)"
                if [ "$now" -ge "$next" ]; then
                    if sudo -n true 2>/dev/null; then
                        misses=0
                    else
                        misses=$((misses + 1))
                        [ "$misses" -ge "$max_misses" ] && exit
                    fi
                    next=$((now + refresh_secs))
                fi
                sleep 2
            done
        ) &
    ) </dev/null >/dev/null 2>&1
}
