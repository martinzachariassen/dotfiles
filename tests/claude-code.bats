#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox

  DOT_DRY_RUN=0 env DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN=0 \
    DOT_MODULE=claude-code DOT_MODULE_DIR="$DOT_ROOT/modules/claude-code" \
    "$BASH" "$DOT_ROOT/modules/claude-code/apply.sh" >/dev/null 2>&1

  BIN="$DOT_TMP/bin"
  mkdir -p "$BIN"
}

teardown() { teardown_sandbox; }

doctor() {
  run env PATH="$BIN:$PATH" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" \
    ANTHROPIC_API_KEY="${API_KEY:-}" \
    ANTHROPIC_AUTH_TOKEN="${AUTH_TOKEN:-}" \
    CLAUDE_CODE_USE_BEDROCK="${USE_BEDROCK:-}" \
    CLAUDE_CODE_USE_VERTEX="${USE_VERTEX:-}" \
    DOT_CLAUDE_KEYCHAIN="${KEYCHAIN:-}" \
    DOT_MODULE=claude-code DOT_MODULE_DIR="$DOT_ROOT/modules/claude-code" \
    "$BASH" "$DOT_ROOT/modules/claude-code/doctor.sh"
}

with_settings() {
  printf 'schema = 1\n\n[modules]\nenabled = ["claude-code"]\n\n[settings.claude-code]\n%s\n' \
    "$1" >"$DOT_CONFIG"
}

with_keychain() {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s"\nexit %s\n' \
    "$DOT_TMP/security-calls" "$1" >"$BIN/security"
  chmod +x "$BIN/security"
}

@test "auth: a keychain item is a machine that is signed in" {
  with_keychain 0
  doctor
  [ "$status" -eq 0 ]
  says auth 'signed in'
}

@test "auth: no keychain item names the command that creates one" {
  with_keychain 44
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"claude auth login"* ]]
}

@test "auth: the keychain item it looked for is named, being the fragile half" {
  with_keychain 44
  doctor
  [[ $output == *"Claude Code-credentials"* ]]
}

@test "auth: the item name is an input, so a machine can follow it when it moves" {
  with_keychain 44
  KEYCHAIN='Claude Code-credentials-v2'
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *'Claude Code-credentials-v2'* ]]
  [[ $(cat "$DOT_TMP/security-calls") == *'Claude Code-credentials-v2'* ]]
}

@test "auth: an API key in the environment is a signed-in machine too" {
  with_keychain 44
  API_KEY=sk-ant-not-a-real-key
  doctor
  [ "$status" -eq 0 ]
  says auth 'ANTHROPIC_API_KEY is set'
}

@test "auth: a bearer token is a signed-in machine too" {
  with_keychain 44
  AUTH_TOKEN=not-a-real-token
  doctor
  [ "$status" -eq 0 ]
  says auth 'ANTHROPIC_AUTH_TOKEN is set'
}

@test "auth: a machine pointed at Bedrock is not a machine that owes a login" {
  with_keychain 44
  USE_BEDROCK=1
  doctor
  [ "$status" -eq 0 ]
  says auth 'pointed at Bedrock, which brings its own credentials'
}

@test "auth: the same for Vertex" {
  with_keychain 44
  USE_VERTEX=1
  doctor
  [ "$status" -eq 0 ]
  says auth 'pointed at Vertex AI, which brings its own credentials'
}

@test "auth: a variable set to 0 is not a cloud provider" {
  with_keychain 44
  USE_BEDROCK=0
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"claude auth login"* ]]
}

@test "auth: auth_check = false is the way out when the item is renamed" {
  with_settings 'auth_check = false'
  with_keychain 44
  doctor
  [ "$status" -eq 0 ]
  [[ $output != *auth* ]]
}

@test "auth: the check speaks by default, with no settings table at all" {
  with_keychain 44
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
}

@test "auth: the secret itself is never read" {
  with_keychain 0
  doctor
  [ "$status" -eq 0 ]
  local calls
  calls=$(cat "$DOT_TMP/security-calls")
  [[ $calls == *"find-generic-password"* ]]
  [[ $calls != *" -w"* ]]
}

@test "auth: the check writes nothing, keychain or not" {
  with_keychain 44
  local before
  before=$(home_snapshot)
  doctor
  [ "$(home_snapshot)" = "$before" ]
}
