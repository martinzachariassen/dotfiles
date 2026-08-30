#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_containers() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# Gated on nothing: colima is core-tier.

doctor_containers() {
    # Containers. The failure that actually bites is silent: colima's home follows
    # $XDG_CONFIG_HOME only while ~/.colima is absent, so anything that starts it
    # without that variable strands the managed template and every later shell with
    # it. Cheap to check, invisible otherwise.
    section "Containers (colima)"
    if command -v colima >/dev/null 2>&1; then
        if [ -d "$HOME/.colima" ]; then
            fail "~/.colima shadows ~/.config/colima — the managed VM template is ignored. Fix: colima delete && rm -rf ~/.colima && chezapply"
        else
            pass "colima home is ~/.config/colima"
        fi
        if [ "$(uname -s)" = "Darwin" ]; then
            if launchctl print "gui/$(id -u)/no.mlz.colima" >/dev/null 2>&1; then
                pass "login agent registered"
            else
                warn "colima login agent not registered — the VM won't start at login. Run: chezapply"
            fi
        fi
        if colima status >/dev/null 2>&1; then
            pass "VM running"
            if docker info >/dev/null 2>&1; then
                pass "docker talks to the VM ($(docker context show 2>/dev/null) context)"
            else
                fail "docker cannot reach the daemon despite a running VM — check: colima status"
            fi
        else
            note "colima VM stopped — start it with: colima start"
        fi
        # Homebrew installs the plugins outside the CLI's search path; without the
        # managed symlinks `docker compose` is simply an unknown command.
        for plugin in docker-compose docker-buildx; do
            if [ -e "$HOME/.docker/cli-plugins/$plugin" ]; then
                pass "$plugin plugin linked"
            else
                warn "$plugin not linked into ~/.docker/cli-plugins — run: chezapply"
            fi
        done
    else
        fail "colima missing — there is no container runtime on this Mac. Run: chezapply"
    fi
    # Legacy guard: Docker Desktop was replaced by colima.
    if [ -d "/Applications/Docker.app" ]; then
        warn "Docker Desktop still installed — it fights colima over ~/.docker. Remove with: brew uninstall --cask docker-desktop"
    fi
}
