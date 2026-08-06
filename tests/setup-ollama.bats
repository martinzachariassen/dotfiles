#!/usr/bin/env bats
# Coverage for setup-ollama.sh's ollama-not-installed and already-running
# paths, stubbed via a fake `ollama` on PATH. The two "actually start it"
# branches (brew services / raw `ollama serve &`) aren't covered here — they'd
# need a real or heavily-stubbed brew/background-process story to test
# meaningfully.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SETUP_OLLAMA="$REPO_ROOT/scripts/bin/setup-ollama.sh"
    STUB_BIN="$(mktemp -d)"
}

teardown() {
    rm -rf "${STUB_BIN:-}"
}

@test "setup-ollama.sh fails loudly when log.sh is missing" {
    iso="$(mktemp -d)"
    mkdir -p "$iso/scripts/bin" # no scripts/lib ⇒ log.sh is unreachable
    cp "$SETUP_OLLAMA" "$iso/scripts/bin/setup-ollama.sh"
    run bash "$iso/scripts/bin/setup-ollama.sh"
    rm -rf "$iso"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]]
    [[ "$output" == *"log.sh"* ]]
}

@test "setup-ollama.sh exits with guidance when ollama is not installed" {
    run env PATH="/usr/bin:/bin" bash "$SETUP_OLLAMA"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ollama not found"* ]]
    [[ "$output" == *"Brewfile.mac-apps"* ]]
}

@test "setup-ollama.sh is a no-op when ollama is already running" {
    cat >"$STUB_BIN/ollama" <<'EOF'
#!/usr/bin/env bash
[ "$1" = list ] && exit 0
exit 1
EOF
    chmod +x "$STUB_BIN/ollama"
    run env PATH="$STUB_BIN:/usr/bin:/bin" bash "$SETUP_OLLAMA"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ollama is already running"* ]]
}
