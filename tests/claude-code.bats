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

doctor() {
  run env PATH="$BIN:$PATH" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" \
    ANTHROPIC_API_KEY="${API_KEY:-}" \
    DOT_MODULE=claude-code DOT_MODULE_DIR="$DOT_ROOT/modules/claude-code" \
    "$BASH" "$DOT_ROOT/modules/claude-code/doctor.sh"
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

@test "auth: an API key in the environment is a signed-in machine too" {
  # Claude Code authenticates either way, so asking only the keychain would
  # warn at a machine that works.
  with_keychain 44
  API_KEY=sk-ant-not-a-real-key
  doctor
  [ "$status" -eq 0 ]
  says auth 'ANTHROPIC_API_KEY is set'
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
