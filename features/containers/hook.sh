#!/usr/bin/env bash
# Registers the colima launchd agent, prunes Docker Desktop's leftovers, and
# clears the ~/.colima directory that would shadow the managed config.
#
# Invoked by run_onchange_after_07-colima.sh.tmpl, which keeps the darwin guard
# and passes the destination home — a render-time value this script cannot know.

set -euo pipefail

home="${1:-$HOME}"
agents="$home/Library/LaunchAgents"
# Homebrew's absolute path, not PATH: chezmoi runs hooks with a login-less
# environment. Overridable so the tests can drive the branches below.
COLIMA_BIN="${COLIMA_BIN:-/opt/homebrew/bin/colima}"

echo "▶ colima"

if [ ! -x "$COLIMA_BIN" ]; then
    echo "  ! colima not installed — brew bundle should have. Run: chezapply"
    exit 0
fi

# launchd writes stdout/stderr here and will not create the directory.
mkdir -p "$home/.local/state/colima/logs"

# A bare ~/.colima outranks $XDG_CONFIG_HOME inside colima, which would strand
# the managed template at ~/.config/colima and start an unconfigured VM instead.
# Empty means something created it by accident; populated means a real instance
# lives there and only its owner can decide to move it.
if [ -d "$home/.colima" ]; then
    if [ -z "$(ls -A "$home/.colima" 2>/dev/null)" ]; then
        rmdir "$home/.colima"
        echo "  ✓ removed an empty ~/.colima (it would shadow ~/.config/colima)"
    else
        echo "  ! ~/.colima exists and shadows ~/.config/colima — the managed"
        echo "    template is being ignored. Move it: colima delete && rm -rf ~/.colima"
    fi
fi

# Docker Desktop left one dangling symlink per plugin behind. Only symlinks whose
# target is gone are pruned; the managed compose/buildx links resolve and stay.
plugins="$home/.docker/cli-plugins"
if [ -d "$plugins" ]; then
    pruned=0
    for link in "$plugins"/*; do
        [ -L "$link" ] || continue
        [ -e "$link" ] && continue
        rm -f "$link"
        pruned=$((pruned + 1))
    done
    if [ "$pruned" -gt 0 ]; then
        echo "  ✓ pruned $pruned dangling cli-plugin symlink(s)"
    fi
fi

plist="$agents/no.mlz.colima.plist"
if [ ! -f "$plist" ]; then
    echo "  ! $plist missing — apply did not render it"
else
    launchctl bootout "gui/$(id -u)/no.mlz.colima" 2>/dev/null || true
    # launchctl's own message is kept: bootstrap can fail transiently while a
    # boot-out is still settling, and "could not register" alone gives whoever
    # reads the apply log nothing to act on.
    if err="$(launchctl bootstrap "gui/$(id -u)" "$plist" 2>&1)"; then
        echo "  ✓ agent registered — colima starts at login"
    else
        echo "  ! could not register the agent: ${err:-no message from launchctl}"
        echo "    Retry with: chezapply — or inspect: launchctl print gui/$(id -u)"
    fi
fi

# The template shapes a VM at creation only, so an existing instance keeps the
# shape it was built with no matter how often this runs.
if "$COLIMA_BIN" list 2>/dev/null | grep -q '^default'; then
    echo "  Template changes reach an existing VM only via: colima delete && colima start"
fi

echo "  First boot downloads the VM image. Follow: tail -f ~/.local/state/colima/logs/startup.log"
