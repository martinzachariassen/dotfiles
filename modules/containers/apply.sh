#!/usr/bin/env bash
#
# Link Homebrew's compose and buildx into ~/.docker/cli-plugins, the only place
# the docker CLI looks. Linked rather than set via cliPluginsExtraDirs in
# ~/.docker/config.json, which `docker login` owns. Targets are outside
# $DOT_ROOT, so remove.sh has to name them.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

brew_load || die 'Homebrew is not on PATH; cannot find the docker plugins'

plugin_dir="$(brew --prefix)/lib/docker/cli-plugins"

for plugin in docker-compose docker-buildx; do
  if [[ -x "$plugin_dir/$plugin" ]]; then
    fs_link "$plugin_dir/$plugin" "$HOME/.docker/cli-plugins/$plugin"
  else
    warn plugins "$plugin is not installed -- brew bundle should have. Run: dot apply"
  fi
done
