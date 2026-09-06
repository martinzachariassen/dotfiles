#!/usr/bin/env bats
#
# modules/containers/remove.sh. The docker plugin links point into Homebrew's
# prefix, so the $DOT_ROOT sweep in uninstall.sh never sees them: this hook is
# the only thing that will ever mention them.

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

# no_brew -- nothing on PATH, and brew_load's absolute fallback pointed at a
# path that does not exist. Both are needed: the fallback is what makes
# `bash uninstall.sh` work from a shell that never sourced shellenv.
no_brew() {
  mkdir -p "$DOT_TMP/empty"
  DOT_BREW_BIN="$DOT_TMP/no-such-brew" remove "$DOT_TMP/empty"
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
  # Silence was the bug. These point outside $DOT_ROOT, so a hook that says
  # nothing leaves them with nothing left in the world that knows they exist.
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
