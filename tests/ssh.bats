#!/usr/bin/env bats
#
# modules/ssh: the tracked config and doctor.sh name the same socket, and
# neither side is written down here -- a constant would be the third copy.

load helper

setup() {
  setup_sandbox
  SSH_CONFIG="$DOT_ROOT/modules/ssh/home/.ssh/config"
  DOCTOR="$DOT_ROOT/modules/ssh/doctor.sh"

  # An ssh-add that reports one key. Shadowed by default so every socket test
  # says only what it is about; the tests about the agent's answer set their
  # own. A real ssh-add here would reach the DEVELOPER's 1Password.
  SSH_ADD="$DOT_TMP/ssh-add"
  with_agent 0 '256 SHA256:aaaa SSH Key (ED25519)'
}

teardown() { teardown_sandbox; }

# with_agent EXIT [TEXT] -- ssh-add's three answers. 0 listed keys, 1 an agent
# holding none, 2 an agent that could not be reached: the codes are the whole
# distinction. The listing goes in a file the stub cats rather than into the
# generated script, the same reason macos-defaults.bats does it -- a key line
# carries parentheses and slashes, and escaping them is a second thing to get
# wrong.
with_agent() {
  printf '%s' "${2:+$2
}" >"$DOT_TMP/agent-answer"
  printf '#!/usr/bin/env bash\ncat "%s"\nexit %s\n' "$DOT_TMP/agent-answer" "$1" >"$SSH_ADD"
  chmod +x "$SSH_ADD"
}

# The socket doctor.sh tests, with $HOME substituted textually (no eval on a
# value read out of a file).
doctor_socket() {
  local s
  s=$(sed -n 's/^sock="\(.*\)"$/\1/p' "$DOCTOR")
  printf '%s\n' "${s//\$HOME/$1}"
}

doctor() {
  run env HOME="${1:-$HOME}" DOT_ROOT="$DOT_ROOT" DOT_SSH_ADD="$SSH_ADD" \
    "$BASH" "$DOCTOR"
}

# live_socket DIR -- a bound unix socket where doctor.sh looks, under a SHORT
# $HOME: socket paths are capped at 104 bytes on macOS and the sandbox path
# plus "Library/Group Containers/..." exceeds it. Echoes the home to use.
live_socket() {
  local short sock
  short=$(mktemp -d /tmp/dot-ssh.XXXXXX)
  sock=$(doctor_socket "$short")
  mkdir -p "$(dirname "$sock")"
  python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$sock"
  printf '%s\n' "$short"
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
  # The hole this check was added for. A locked vault, or a key the agent was
  # never told to expose, leaves the socket exactly as it is here -- and the
  # module reported green while every push and every signature failed.
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
  # Two different machines and two different fixes: ssh-add exits 1 for an
  # agent holding nothing and 2 for one it never spoke to. Collapsing them
  # sends you to the 1Password key list over a socket nothing is serving.
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
  # The reason this check is allowed in a read-only run at all. `ssh-add -l` is
  # answered without a 1Password approval dialog; anything that signs raises
  # one, and a check that blocks on a human is worse than no check.
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

# --- what the module actually ships -----------------------------------------

@test "the agent config names a vault, so a key outside the default one is offered" {
  local f="$DOT_ROOT/modules/ssh/home/.config/1Password/ssh/agent.toml"
  [ -f "$f" ]
  grep -q '^\[\[ssh-keys\]\]$' "$f"
  grep -Eq '^vault = "[^"]+"$' "$f"
}

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
