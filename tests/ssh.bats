#!/usr/bin/env bats
#
# modules/ssh: the tracked config and doctor.sh name the same socket, and
# neither side is written down here -- a constant would be the third copy.

load helper

setup() {
  setup_sandbox
  SSH_CONFIG="$DOT_ROOT/modules/ssh/home/.ssh/config"
  DOCTOR="$DOT_ROOT/modules/ssh/doctor.sh"
}

teardown() { teardown_sandbox; }

# The socket doctor.sh tests, with $HOME substituted textually (no eval on a
# value read out of a file).
doctor_socket() {
  local s
  s=$(sed -n 's/^sock="\(.*\)"$/\1/p' "$DOCTOR")
  printf '%s\n' "${s//\$HOME/$1}"
}

doctor() {
  run env HOME="${1:-$HOME}" DOT_ROOT="$DOT_ROOT" "$BASH" "$DOCTOR"
}

# --- the invariant ----------------------------------------------------------

@test "the socket doctor.sh checks is the one ssh is told to use" {
  local from_config from_doctor
  from_config=$(sed -n 's/^[[:space:]]*IdentityAgent[[:space:]]\{1,\}//p' \
    "$SSH_CONFIG" | tr -d '"')
  from_config=${from_config/#\~/$HOME}
  from_doctor=$(doctor_socket "$HOME")

  # Both non-empty first, or a rename makes this pass over nothing forever.
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

# --- doctor.sh --------------------------------------------------------------

@test "doctor: a live agent socket passes" {
  command -v python3 >/dev/null || skip 'no python3 to make a unix socket'

  # A SHORT $HOME: unix socket paths are capped at 104 bytes on macOS, and the
  # sandbox path plus "Library/Group Containers/..." exceeds it.
  local short sock
  short=$(mktemp -d /tmp/dot-ssh.XXXXXX)
  sock=$(doctor_socket "$short")
  mkdir -p "$(dirname "$sock")"
  python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$sock"

  doctor "$short"
  rm -rf "$short"

  [ "$status" -eq 0 ]
  [[ $output == *"live"* ]]
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

# --- what the module actually ships -----------------------------------------

@test "syntax: the shipped ssh config parses" {
  # Not covered by shellcheck/shfmt. A bad keyword makes ssh exit 255 on EVERY
  # connection, including the one you would pull the fix with.
  command -v ssh >/dev/null || skip 'no ssh on this machine'
  run ssh -G -F "$SSH_CONFIG" github.com
  [ "$status" -eq 0 ] || {
    echo "$output"
    return 1
  }
}

@test "the config actually points github.com at an agent" {
  # Parsing is not matching: a `Host github.com-work` typo parses and applies to nothing.
  command -v ssh >/dev/null || skip 'no ssh on this machine'
  run ssh -G -F "$SSH_CONFIG" github.com
  local resolved
  resolved=$(printf '%s\n' "$output" | sed -n 's/^identityagent //p')
  [ -n "$resolved" ]
  [ "$resolved" != none ]
}
