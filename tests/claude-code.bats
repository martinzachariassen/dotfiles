#!/usr/bin/env bats
#
# modules/claude-code/doctor.sh -- the sign-in half. The settings half is
# covered generically by contract.bats, which holds all three hooks to the same
# derivation of $want from data/settings.json.
#
# Sign-in is the one check here that reaches outside $HOME entirely: the token
# is a login keychain item, not a file, which is why no amount of comparing
# ~/.claude/settings.json could ever have noticed a machine that cannot talk to
# Anthropic at all.

load helper

setup() {
  setup_sandbox

  # The settings half has to pass, or its failures are what the output says.
  # The real apply.sh, not a printf'd lookalike: a hand-written settings.json
  # is a second definition of what doctor.sh compares against.
  DOT_DRY_RUN=0 env DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN=0 \
    DOT_MODULE=claude-code DOT_MODULE_DIR="$DOT_ROOT/modules/claude-code" \
    "$BASH" "$DOT_ROOT/modules/claude-code/apply.sh" >/dev/null 2>&1

  BIN="$DOT_TMP/bin"
  mkdir -p "$BIN"
}

teardown() { teardown_sandbox; }

# Every authentication route is passed explicitly, empty by default: a
# developer running the suite with one of these exported would otherwise decide
# the result, and the branch that matters is the one where none is set.
#
# DOT_CLAUDE_KEYCHAIN is passed the same way and must stay EMPTY here, not set
# to the default: empty falls through to the hook's own literal, which is what
# leaves "the keychain item it looked for is named" testing the hook rather
# than this line.
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

# with_settings LINE -- this module's settings table. The module list has to
# name it, or module_setting reads a table nothing enabled.
with_settings() {
  printf 'schema = 1\n\n[modules]\nenabled = ["claude-code"]\n\n[settings.claude-code]\n%s\n' \
    "$1" >"$DOT_CONFIG"
}

# with_keychain EXIT -- a `security` that answers as the real one does: 0 when
# the item is there, 44 when it is not. Shadowed on PATH rather than skipped,
# because the developer's own keychain would otherwise decide the result.
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
  # The deliverable: every other line in this module is about a settings key,
  # and none of them says why `claude` opens a browser on a fresh Mac.
  with_keychain 44
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"claude auth login"* ]]
}

@test "auth: the keychain item it looked for is named, being the fragile half" {
  # Anthropic owns that string. A machine where it changed would otherwise
  # warn forever with nothing on screen to say why.
  with_keychain 44
  doctor
  [[ $output == *"Claude Code-credentials"* ]]
}

@test "auth: the item name is an input, so a machine can follow it when it moves" {
  # The escape hatch for the fragile half, and it has to reach `security`
  # itself: a message naming the new item while the question still asked for
  # the old one is a check that answers about nothing.
  with_keychain 44
  KEYCHAIN='Claude Code-credentials-v2'
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *'Claude Code-credentials-v2'* ]]
  [[ $(cat "$DOT_TMP/security-calls") == *'Claude Code-credentials-v2'* ]]
}

@test "auth: an API key in the environment is a signed-in machine too" {
  # Claude Code authenticates either way, so asking only the keychain would
  # warn at a machine that works.
  with_keychain 44
  API_KEY=sk-ant-not-a-real-key
  doctor
  [ "$status" -eq 0 ]
  says auth 'ANTHROPIC_API_KEY is set'
}

@test "auth: a bearer token is a signed-in machine too" {
  # A gateway in front of the API. No keychain item will ever exist on such a
  # machine, so the keychain question is the wrong one to answer it with.
  with_keychain 44
  AUTH_TOKEN=not-a-real-token
  doctor
  [ "$status" -eq 0 ]
  says auth 'ANTHROPIC_AUTH_TOKEN is set'
}

@test "auth: a machine pointed at Bedrock is not a machine that owes a login" {
  # AWS carries the credentials, and `claude auth login` is advice that does
  # nothing there -- a yellow line forever with a command that cannot help.
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
  # `CLAUDE_CODE_USE_BEDROCK=0` is how you turn it OFF, and reading any
  # non-empty value as "on" would call that machine authenticated.
  with_keychain 44
  USE_BEDROCK=0
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"claude auth login"* ]]
}

@test "auth: auth_check = false is the way out when the item is renamed" {
  # The last resort. Anthropic owns that service string, and the day it
  # changes every machine here warns forever about a login it already has.
  # Everything this repo reports and cannot fix has an off switch.
  with_settings 'auth_check = false'
  with_keychain 44
  doctor
  [ "$status" -eq 0 ]
  [[ $output != *auth* ]]
}

@test "auth: the check speaks by default, with no settings table at all" {
  # The other half of the setting: a config that never mentions this module
  # must still be asked. A default that silenced it would be a check nobody
  # has ever seen run.
  with_keychain 44
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
}

@test "auth: the secret itself is never read" {
  # `security find-generic-password -w` decrypts, and decrypting is what
  # raises the authorisation dialog. A doctor run may not block on a human.
  with_keychain 0
  doctor
  [ "$status" -eq 0 ]
  local calls
  calls=$(cat "$DOT_TMP/security-calls")
  [[ $calls == *"find-generic-password"* ]]
  [[ $calls != *" -w"* ]]
}

@test "auth: the check writes nothing, keychain or not" {
  # The generic contract.bats snapshot runs doctor.sh with the real `security`
  # on a machine that has the item; this covers the branch it never takes.
  with_keychain 44
  local before
  before=$(home_snapshot)
  doctor
  [ "$(home_snapshot)" = "$before" ]
}
