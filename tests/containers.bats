#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
  PLUGINS="$HOME/.docker/cli-plugins"
  mkdir -p "$PLUGINS"
}

teardown() { teardown_sandbox; }

remove() {
  run env ${1:+PATH="$1"} ${DOT_BREW_BIN:+DOT_BREW_BIN="$DOT_BREW_BIN"} \
    DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN=0 \
    DOT_MODULE=containers DOT_MODULE_DIR="$DOT_ROOT/modules/containers" \
    "$BASH" "$DOT_ROOT/modules/containers/remove.sh"
}

no_brew() {
  mkdir -p "$DOT_TMP/empty"
  DOT_BREW_BIN="$DOT_TMP/no-such-brew" remove "$DOT_TMP/empty"
}

apply() {
  run env PATH="$DOT_TMP/bin:$PATH" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN="${1:-0}" \
    DOT_MODULE=containers DOT_MODULE_DIR="$DOT_ROOT/modules/containers" \
    "$BASH" "$DOT_ROOT/modules/containers/apply.sh"
}

with_prefix() {
  mkdir -p "$DOT_TMP/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$DOT_TMP/brew" >"$DOT_TMP/bin/brew"
  chmod +x "$DOT_TMP/bin/brew"
  mkdir -p "$DOT_TMP/brew/lib/docker/cli-plugins"
}

@test "apply: both plugins are linked, and the run says where" {
  with_prefix
  local dir="$DOT_TMP/brew/lib/docker/cli-plugins"
  printf '#!/bin/sh\n' >"$dir/docker-compose"
  printf '#!/bin/sh\n' >"$dir/docker-buildx"
  chmod +x "$dir/docker-compose" "$dir/docker-buildx"

  apply
  [ "$status" -eq 0 ]
  [ -L "$PLUGINS/docker-compose" ]
  [ -L "$PLUGINS/docker-buildx" ]
  says link '~/.docker/cli-plugins/docker-compose'
}

@test "apply: a plugin Homebrew never installed is named, not skipped quietly" {
  with_prefix
  local dir="$DOT_TMP/brew/lib/docker/cli-plugins"
  printf '#!/bin/sh\n' >"$dir/docker-compose"
  chmod +x "$dir/docker-compose"

  apply
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  says plugins 'docker-buildx is not installed -- brew bundle should have. Run: dot apply'
  [ -L "$PLUGINS/docker-compose" ]
  [ ! -e "$PLUGINS/docker-buildx" ]
}

@test "apply: a dry run names the links and makes none" {
  with_prefix
  local dir="$DOT_TMP/brew/lib/docker/cli-plugins"
  printf '#!/bin/sh\n' >"$dir/docker-compose"
  printf '#!/bin/sh\n' >"$dir/docker-buildx"
  chmod +x "$dir/docker-compose" "$dir/docker-buildx"
  local before
  before=$(home_snapshot)

  apply 1
  [ "$status" -eq 0 ]
  says link '~/.docker/cli-plugins/docker-compose'
  [ "$(home_snapshot)" = "$before" ]
}

@test "apply: no Homebrew at all stops before it guesses a path" {
  mkdir -p "$DOT_TMP/empty"
  run env PATH="$DOT_TMP/empty" DOT_BREW_BIN="$DOT_TMP/no-such-brew" \
    DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN=0 \
    DOT_MODULE=containers DOT_MODULE_DIR="$DOT_ROOT/modules/containers" \
    "$BASH" "$DOT_ROOT/modules/containers/apply.sh"
  [ "$status" -ne 0 ]
  [[ $output == *"Homebrew is not on PATH"* ]]
  [ ! -e "$PLUGINS/docker-compose" ]
}

@test "remove: a link into Homebrew's prefix is taken back" {
  command -v brew >/dev/null 2>&1 || skip 'no Homebrew on this machine'
  local dir
  dir="$(brew --prefix)/lib/docker/cli-plugins"
  ln -s "$dir/docker-compose" "$PLUGINS/docker-compose"

  remove
  [ ! -e "$PLUGINS/docker-compose" ]
}

@test "remove: a link Docker Desktop put there is left alone, silently" {
  command -v brew >/dev/null 2>&1 || skip 'no Homebrew on this machine'
  ln -s /Applications/Docker.app/Contents/Resources/cli-plugins/docker-buildx \
    "$PLUGINS/docker-buildx"

  remove
  [ -L "$PLUGINS/docker-buildx" ]
  [ -z "$output" ]
}

@test "remove: a real file where a plugin link would be is never touched" {
  printf 'mine\n' >"$PLUGINS/docker-compose"
  remove
  [ "$(cat "$PLUGINS/docker-compose")" = "mine" ]
}

@test "remove: with no Homebrew to prove ownership, the links are named" {
  ln -s /somewhere/docker-compose "$PLUGINS/docker-compose"

  no_brew
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"docker-compose"* ]]
  [ -L "$PLUGINS/docker-compose" ]
}

@test "remove: with no Homebrew and no links, nothing is claimed" {
  no_brew
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

doctor() {
  mkdir -p "$DOT_TMP/bin"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$DOT_TMP/bin/colima"
  chmod +x "$DOT_TMP/bin/colima"

  run env "$@" HOME="$HOME" DOT_ROOT="$DOT_ROOT" PATH="$DOT_TMP/bin:$PATH" \
    "$BASH" "$DOT_ROOT/modules/containers/doctor.sh"
}

@test "the DOCKER_HOST doctor.sh wants is the one .zshenv exports" {
  local from_zshenv from_doctor
  from_zshenv=$(sed -n 's/^ *export DOCKER_HOST="\(.*\)"$/\1/p' \
    "$DOT_ROOT/modules/zsh/home/.zshenv")
  from_doctor=$(sed -n 's/^ *want_host="\(.*\)"$/\1/p' \
    "$DOT_ROOT/modules/containers/doctor.sh")

  [ -n "$from_zshenv" ] || {
    echo 'no DOCKER_HOST export in modules/zsh/home/.zshenv'
    return 1
  }
  [ -n "$from_doctor" ] || {
    echo 'no want_host assignment in modules/containers/doctor.sh'
    return 1
  }
  [ "$from_zshenv" = "$from_doctor" ] || {
    echo "zshenv: $from_zshenv"
    echo "doctor: $from_doctor"
    return 1
  }
}

@test "the socket override doctor.sh wants is the one .zshenv exports" {
  local from_zshenv from_doctor
  from_zshenv=$(sed -n 's/^ *export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=\(.*\)$/\1/p' \
    "$DOT_ROOT/modules/zsh/home/.zshenv")
  from_doctor=$(sed -n "s/^ *want_override='\\(.*\\)'\$/\\1/p" \
    "$DOT_ROOT/modules/containers/doctor.sh")

  [ -n "$from_zshenv" ] || {
    echo 'no TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE export in modules/zsh/home/.zshenv'
    return 1
  }
  [ -n "$from_doctor" ] || {
    echo 'no want_override assignment in modules/containers/doctor.sh'
    return 1
  }
  [ "$from_zshenv" = "$from_doctor" ] || {
    echo "zshenv: $from_zshenv"
    echo "doctor: $from_doctor"
    return 1
  }
}

@test "doctor: no VM yet says nothing about DOCKER_HOST" {
  doctor -u DOCKER_HOST -u TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE
  [[ $output != *"DOCKER_HOST"* ]]
}

@test "doctor: the right env passes once a VM exists" {
  mkdir -p "$HOME/.colima/default"
  doctor -u DOCKER_HOST -u TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE \
    DOCKER_HOST="unix://$HOME/.colima/default/docker.sock" \
    TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
  [[ $output == *"DOCKER_HOST"*"set for Testcontainers"* ]]
}

@test "doctor: missing env fails without a next shell to blame" {
  mkdir -p "$HOME/.colima/default"
  doctor -u DOCKER_HOST -u TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *"not set"* ]]
}

@test "doctor: missing env is excused once .zshenv is linked" {
  mkdir -p "$HOME/.colima/default"
  mkdir -p "$(dirname "$HOME/.zshenv")"
  ln -s "$DOT_ROOT/modules/zsh/home/.zshenv" "$HOME/.zshenv"

  doctor -u DOCKER_HOST -u TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE
  [[ $output == *"next shell"* ]]
  [[ $output != *"not set"* ]]
}
