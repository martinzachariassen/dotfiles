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
sudo_keep_warm() {
    local watch_pid="$1" refresh_secs="${2:-240}"
    (
        (
            local refresh_in=0
            while kill -0 "$watch_pid" 2>/dev/null; do
                if [ "$refresh_in" -le 0 ]; then
                    sudo -n true 2>/dev/null || exit
                    refresh_in="$refresh_secs"
                fi
                sleep 2
                refresh_in=$((refresh_in - 2))
            done
        ) &
    ) </dev/null >/dev/null 2>&1
}
