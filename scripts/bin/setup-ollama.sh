#!/usr/bin/env bash
# setup-ollama.sh — start Ollama as a background service (installed by the
# mac-apps Homebrew module). Idempotent; does not download models.

set -euo pipefail

# log.sh is a committed sibling; fail loudly if a checkout is missing it.
_UI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$_UI_DIR/../lib/log.sh" ]; then
    printf 'setup-ollama: missing %s\n' "$_UI_DIR/../lib/log.sh" >&2
    exit 1
fi
# shellcheck source=../lib/log.sh
. "$_UI_DIR/../lib/log.sh"
ui_init_status

info() { s_info "$1"; }
ok() { s_pass "$1"; }
warn() { s_warn "$1"; }

if ! command -v ollama >/dev/null 2>&1; then
    echo "setup-ollama: ollama not found. Install the workstation apps first:" >&2
    echo "  brew bundle install --file=packages/Brewfile.mac-apps" >&2
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

echo "${NODE} Ollama service"

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
