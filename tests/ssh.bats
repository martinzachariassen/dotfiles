#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
  SSH_CONFIG="$DOT_ROOT/modules/ssh/home/.ssh/config"
  DOCTOR="$DOT_ROOT/modules/ssh/doctor.sh"

  SSH_ADD="$DOT_TMP/ssh-add"
  with_agent 0 '256 SHA256:aaaa SSH Key (ED25519)'
}

teardown() { teardown_sandbox; }

with_agent() {
  printf '%s' "${2:+$2
}" >"$DOT_TMP/agent-answer"
  printf '#!/usr/bin/env bash\ncat "%s"\nexit %s\n' "$DOT_TMP/agent-answer" "$1" >"$SSH_ADD"
  chmod +x "$SSH_ADD"
}

doctor_socket() {
  local s
  s=$(sed -n 's/^sock="\(.*\)"$/\1/p' "$DOCTOR")
  printf '%s\n' "${s//\$HOME/$1}"
}

doctor() {
  run env HOME="${1:-$HOME}" DOT_ROOT="$DOT_ROOT" DOT_SSH_ADD="$SSH_ADD" \
    "$BASH" "$DOCTOR"
}

live_socket() {
  local short sock
  short=$(mktemp -d /tmp/dot-ssh.XXXXXX)
  sock=$(doctor_socket "$short")
  mkdir -p "$(dirname "$sock")"
  python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$sock"
  printf '%s\n' "$short"
}

@test "the socket doctor.sh checks is the one ssh is told to use" {
  local from_config from_doctor
  from_config=$(sed -n 's/^[[:space:]]*IdentityAgent[[:space:]]\{1,\}//p' \
    "$SSH_CONFIG" | tr -d '"')
  from_config=${from_config/#\~/$HOME}
  from_doctor=$(doctor_socket "$HOME")

  [ -n "$from_config" ] || {
    echo 'no IdentityAgent line in the shipped ssh config'
    return 1
  }
  [ -n "$from_doctor" ] || {
    echo 'no sock= assignment in ssh/doctor.sh'
    return 1
  }
  [ "$from_config" = "$from_doctor" ] || {
    echo "config: $from_config"
    echo "doctor: $from_doctor"
    return 1
  }
}

@test "doctor: a live agent holding a key passes, and counts it" {
  command -v python3 >/dev/null || skip 'no python3 to make a unix socket'

  local short
  short=$(live_socket)
  doctor "$short"
  rm -rf "$short"

  [ "$status" -eq 0 ]
  [[ $output == *"live"* ]]
  [[ $output == *"1 key"* ]]
}

@test "doctor: a live socket serving no keys is not a healthy machine" {
  command -v python3 >/dev/null || skip 'no python3 to make a unix socket'

  local short
  short=$(live_socket)
  with_agent 1
  doctor "$short"
  rm -rf "$short"

  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"no keys"* ]]
  [[ $output == *"Developer"* ]]
  [[ $output == *"agent.toml"* ]]
}

@test "doctor: an agent that cannot be reached is told apart from an empty one" {
  command -v python3 >/dev/null || skip 'no python3 to make a unix socket'

  local short
  short=$(live_socket)
  with_agent 2
  doctor "$short"
  rm -rf "$short"

  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"did not answer"* ]]
  [[ $output != *"no keys"* ]]
}

@test "doctor: listing keys never asks the agent to sign" {
  command -v python3 >/dev/null || skip 'no python3 to make a unix socket'

  local short calls
  short=$(live_socket)
  calls="$DOT_TMP/ssh-add-calls"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s"\n' "$calls" >"$SSH_ADD"
  chmod +x "$SSH_ADD"

  doctor "$short"
  rm -rf "$short"

  [ "$(cat "$calls")" = "-l" ]
}

@test "doctor: a missing socket warns without failing" {
  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"not running"* ]]
  [[ $output == *"Developer"* ]]
}

@test "doctor: an ordinary file at the socket path is not healthy" {
  local sock
  sock=$(doctor_socket "$HOME")
  mkdir -p "$(dirname "$sock")"
  printf 'not a socket\n' >"$sock"

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
}

@test "the agent config names a vault, so a key outside the default one is offered" {
  local f="$DOT_ROOT/modules/ssh/home/.config/1Password/ssh/agent.toml"
  [ -f "$f" ]
  grep -q '^\[\[ssh-keys\]\]$' "$f"
  grep -Eq '^vault = "[^"]+"$' "$f"
}

@test "syntax: the shipped ssh config parses" {
  command -v ssh >/dev/null || skip 'no ssh on this machine'
  run ssh -G -F "$SSH_CONFIG" github.com
  [ "$status" -eq 0 ] || {
    echo "$output"
    return 1
  }
}

@test "the config actually points github.com at an agent" {
  command -v ssh >/dev/null || skip 'no ssh on this machine'
  run ssh -G -F "$SSH_CONFIG" github.com
  local resolved
  resolved=$(printf '%s\n' "$output" | sed -n 's/^identityagent //p')
  [ -n "$resolved" ]
  [ "$resolved" != none ]
}
