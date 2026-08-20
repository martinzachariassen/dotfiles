#!/usr/bin/env bats
# Behavioural tests for scripts/bin/signing.sh, which backs `chezsign`: set the
# git signing key on a machine that deferred it, replaying every other saved
# answer so nothing else is re-asked. Runs the real script against a stubbed
# chezmoi + ssh-add and a real (dead) unix socket standing in for the agent.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/scripts/bin/signing.sh"
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"

    STUBS="$(mktemp -d)"
    INIT_LOG="$STUBS/init.log"
    : >"$INIT_LOG"

    KEY_A="ssh-ed25519 AAAAKEYAAA"
    KEY_B="ssh-ed25519 BBBBKEYBBB"

    # chezmoi stub: `data --format=json` returns the saved answers; `init` logs.
    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
if [ "\$1" = data ]; then
    printf '%s\n' "\${FAKE_DATA:-{\}}"
    exit 0
fi
if [ "\$1" = init ]; then
    shift
    printf '%s\n' "\$*" >>"$INIT_LOG"
    exit 0
fi
exit 0
EOF
    chmod +x "$STUBS/chezmoi"

    # ssh-add stub: prints whatever the test puts in FAKE_AGENT_KEYS.
    cat >"$STUBS/ssh-add" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_AGENT_KEYS:-}" ] || exit 1
printf '%s\n' "$FAKE_AGENT_KEYS"
EOF
    chmod +x "$STUBS/ssh-add"

    # A real AF_UNIX socket file, so the `-S` guard passes without a live agent.
    AGENT_SOCK="$STUBS/agent.sock"
    python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$AGENT_SOCK"

    DATA_FULL='{"name":"Ada L","email":"ada@example.com","profile":"personal","signingMode":"1password","signingKey":"","modules":["theme","jvmStack"]}'

    export PATH="$STUBS:$PATH"
}

teardown() { rm -rf "$STUBS"; }

run_sign() { # extra env is set by the caller
    run env PATH="$STUBS:$PATH" DRY_RUN=1 CHEZSIGN_AGENT_SOCK="$AGENT_SOCK" \
        FAKE_DATA="$FAKE_DATA" FAKE_AGENT_KEYS="${FAKE_AGENT_KEYS:-}" \
        bash "$SCRIPT" "$@"
}

@test "--help explains the verb without touching chezmoi" {
    FAKE_DATA="$DATA_FULL" run_sign --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: chezsign"* ]]
    [ ! -s "$INIT_LOG" ]
}

@test "signing off is reported, not silently 'fixed'" {
    FAKE_DATA='{"signingMode":"off"}' run_sign
    [ "$status" -eq 0 ]
    [[ "$output" == *"off"* ]]
    [[ "$output" == *"chezsetup --reset"* ]]
    [ ! -s "$INIT_LOG" ]
}

@test "an explicit key is replayed with every other answer preserved" {
    FAKE_DATA="$DATA_FULL" run_sign "$KEY_B"
    [ "$status" -eq 0 ]
    # DRY_RUN prints the command it would run, through printf %q — so spaces
    # arrive backslash-escaped ("Ada\ L"). Strip the escaping before matching.
    local plain="${output//\\/}"
    [[ "$plain" == *"Ada L"* ]]
    [[ "$plain" == *"ada@example.com"* ]]
    [[ "$plain" == *"Profile=personal"* ]]
    [[ "$plain" == *"theme/jvmStack"* ]]
    [[ "$plain" == *"BBBBKEYBBB"* ]]
}

@test "the replayed init passes --force so it cannot stall on a drift prompt" {
    FAKE_DATA="$DATA_FULL" run_sign "$KEY_B"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--force"* ]]
}

@test "the signing mode is replayed unchanged, never reset to a default" {
    FAKE_DATA='{"name":"A","email":"a@b.c","profile":"work","signingMode":"ssh-key","signingKey":"","modules":[]}'
    run_sign "$KEY_B"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ssh-key"* ]]
    [[ "$output" != *"1password"* ]]
}

@test "a trailing agent comment is stripped from the key" {
    FAKE_DATA="$DATA_FULL" run_sign "$KEY_B some trailing comment"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BBBBKEYBBB"* ]]
    [[ "$output" != *"trailing comment"* ]]
}

@test "setting the key that is already configured changes nothing" {
    FAKE_DATA='{"name":"A","email":"a@b.c","profile":"personal","signingMode":"1password","signingKey":"'"$KEY_A"'","modules":[]}'
    run_sign "$KEY_A"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already configured"* ]]
    [ ! -s "$INIT_LOG" ]
}

@test "a key offered by the agent is picked up without being pasted" {
    FAKE_DATA="$DATA_FULL"
    FAKE_AGENT_KEYS="$KEY_A SSH Key"
    run env PATH="$STUBS:$PATH" DRY_RUN=1 YES=1 CHEZSIGN_AGENT_SOCK="$AGENT_SOCK" \
        FAKE_DATA="$DATA_FULL" FAKE_AGENT_KEYS="$KEY_A SSH Key" bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AAAAKEYAAA"* ]]
    # The agent's comment must not reach allowed_signers, which is "<email> <key>".
    [[ "$output" != *"SSH Key"* ]]
}

@test "no agent and no key fails with actionable guidance" {
    FAKE_DATA="$DATA_FULL"
    run env PATH="$STUBS:$PATH" DRY_RUN=1 YES=1 CHEZSIGN_AGENT_SOCK=/nonexistent \
        SSH_AUTH_SOCK= FAKE_DATA="$DATA_FULL" bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no SSH agent keys found"* ]]
    [[ "$output" == *"SSH agent"* ]]
    [ ! -s "$INIT_LOG" ]
}

@test "zshrc defines chezsign, routed through _chez_run" {
    grep -qE '^chezsign\(\) \{' "$ZSHRC"
    sed -n '/^chezsign() {/,/^}/p' "$ZSHRC" | grep -qF '_chez_run scripts/bin/signing.sh'
}

@test "chezhelp lists chezsign" {
    sed -n '/^chezhelp() {/,/^}/p' "$ZSHRC" | grep -qF 'chezsign'
}

@test "the completion script offers chezsign only when the key is deferred" {
    local tmpl="$REPO_ROOT/src/.chezmoiscripts/run_onchange_after_99-completion.sh.tmpl"
    grep -qF 'SIGNKEY' "$tmpl"
    # Guarded on both "signing is on" and "key is empty".
    grep -qF '[ "$SIGNING" != "off" ] && [ -z "$SIGNKEY" ]' "$tmpl"
}
