#!/usr/bin/env bash
# Configure local LLM tooling after enabling the optional AI Brewfile.
#
# Installs the llm-ollama plugin and pulls the default Ollama model set.

set -euo pipefail

MODELS=(
    "qwen2.5-coder:14b"
    "gemma3:12b"
    "llama3.1:8b"
)

usage() {
    cat <<EOF
Usage: scripts/setup-local-llm.sh [--skip-llm-plugin] [--skip-models]

Environment:
  OLLAMA_HOST  Ollama server URL if you do not use the local default.
EOF
}

SKIP_LLM_PLUGIN=0
SKIP_MODELS=0

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-llm-plugin) SKIP_LLM_PLUGIN=1 ;;
        --skip-models) SKIP_MODELS=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "setup-local-llm: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

need() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "setup-local-llm: missing '$1'. Enable the AI feature first: dotfiles features enable ai" >&2
        exit 1
    fi
}

wait_for_ollama() {
    local i
    for i in $(seq 1 30); do
        if ollama list >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

ensure_ollama_running() {
    if ollama list >/dev/null 2>&1; then
        return 0
    fi

    if command -v brew >/dev/null 2>&1; then
        echo "Starting Ollama via brew services..."
        brew services start ollama >/dev/null
    else
        echo "Starting Ollama in the background..."
        ollama serve >/tmp/ollama.log 2>&1 &
    fi

    if ! wait_for_ollama; then
        echo "setup-local-llm: Ollama did not become ready" >&2
        exit 1
    fi
}

install_llm_ollama() {
    [ "$SKIP_LLM_PLUGIN" = "0" ] || return 0
    need llm

    if llm plugins 2>/dev/null | grep -q 'llm-ollama'; then
        echo "llm-ollama plugin already installed"
        return 0
    fi

    echo "Installing llm-ollama plugin..."
    llm install llm-ollama
}

pull_models() {
    [ "$SKIP_MODELS" = "0" ] || return 0
    need ollama
    ensure_ollama_running

    local model
    for model in "${MODELS[@]}"; do
        if ollama list | awk '{print $1}' | grep -Fxq "$model"; then
            echo "Ollama model already present: $model"
        else
            echo "Pulling Ollama model: $model"
            ollama pull "$model"
        fi
    done
}

need ollama
install_llm_ollama
pull_models

echo "Local LLM setup complete."

