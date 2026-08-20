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
# promptly, refreshing sudo every REFRESH_SECS (default 240, inside the
# default 5-min cache).
#
# A refresh that fails does not end the keeper. It used to: `sudo -n true ||
# exit` gave up permanently on the first miss, so one transient failure early in
# a 13-minute `brew bundle` left every later step (macOS defaults) to prompt
# again — after the apply had already promised the password was only needed
# once. Only a run of consecutive failures means the ticket is genuinely gone,
# at which point there is nothing left to keep warm and the later steps prompt
# for themselves.
sudo_keep_warm() {
    local watch_pid="$1" refresh_secs="${2:-240}"
    local max_misses="${SUDO_KEEP_WARM_MAX_MISSES:-3}"
    (
        (
            local refresh_in=0 misses=0
            while kill -0 "$watch_pid" 2>/dev/null; do
                if [ "$refresh_in" -le 0 ]; then
                    if sudo -n true 2>/dev/null; then
                        misses=0
                    else
                        misses=$((misses + 1))
                        [ "$misses" -ge "$max_misses" ] && exit
                    fi
                    refresh_in="$refresh_secs"
                fi
                sleep 2
                refresh_in=$((refresh_in - 2))
            done
        ) &
    ) </dev/null >/dev/null 2>&1
}
