#!/usr/bin/env bash
# setup-ollama.sh — start Ollama as a background service. Ollama is installed by
# the mac-apps Homebrew module (brewfiles/Brewfile.mac-apps).
#
# This script does NOT download any models. Models are large and
# machine-specific, so you pull the ones you want by hand:
#
#   ollama pull qwen2.5-coder:14b
#   ollama run  qwen2.5-coder:14b 'Explain this git error in one paragraph'
#   ollama list
#
# If Ollama runs somewhere other than the local default, set OLLAMA_HOST:
#
#   OLLAMA_HOST=http://localhost:11434 ollama list
#
# Idempotent: safe to re-run. Starting an already-running service is a no-op.
#
# Usage: scripts/setup-ollama.sh

set -euo pipefail

# Shared UI helpers (ui_init_colors). Resolved next to this script so it works
# regardless of the current directory.
_UI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/ui.sh
if [ -r "$_UI_DIR/lib/ui.sh" ]; then
    . "$_UI_DIR/lib/ui.sh"
    ui_init_colors
else
    GREEN=""
    YELLOW=""
    BLUE=""
    RESET=""
fi

info() { echo "  ${BLUE}→${RESET} $1"; }
ok() { echo "  ${GREEN}✓${RESET} $1"; }
warn() { echo "  ${YELLOW}!${RESET} $1"; }

if ! command -v ollama >/dev/null 2>&1; then
    echo "setup-ollama: ollama not found. Install the workstation apps first:" >&2
    echo "  brew bundle install --file=brewfiles/Brewfile.mac-apps" >&2
    echo "  (or run install.sh / chezmoi apply)" >&2
    exit 1
fi

wait_for_ollama() {
    local _
    for _ in $(seq 1 30); do
        if ollama list >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

echo "◆ Ollama service"

if ollama list >/dev/null 2>&1; then
    ok "Ollama is already running"
elif command -v brew >/dev/null 2>&1; then
    info "starting Ollama via brew services"
    brew services start ollama >/dev/null
    if wait_for_ollama; then
        ok "Ollama service started"
    else
        warn "Ollama did not become ready — check: brew services list"
        exit 1
    fi
else
    info "brew not found; starting Ollama in the background"
    ollama serve >/tmp/ollama.log 2>&1 &
    if wait_for_ollama; then
        ok "Ollama started (logs: /tmp/ollama.log)"
    else
        warn "Ollama did not become ready — check /tmp/ollama.log"
        exit 1
    fi
fi

echo
info "Pull the models you want manually, e.g.:"
echo "      ollama pull qwen2.5-coder:14b"
echo "      ollama list"
