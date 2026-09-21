# The only zsh file in $HOME: ZDOTDIR moves the rest into the XDG tree.
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"

# Here, not .zshrc: git can be invoked without an interactive shell. Absolute
# path test, not `command -v`: PATH gains Homebrew only later, in path.zsh.
# `--wait` or `code` returns instantly and git commits an empty message.
if [[ -x /opt/homebrew/bin/code ]]; then
  export EDITOR='code --wait'
  export VISUAL="$EDITOR"
fi

# Here too, not .zshrc: Maven and other JVM tooling run non-interactively.
# Testcontainers does not read the docker context colima registers, so it
# needs the socket named directly. See modules/containers/README.md.
if [[ -d "$HOME/.colima/default" ]]; then
  export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"

  # The mount source Testcontainers gives its Ryuk container has to resolve
  # INSIDE the VM, where dockerd's socket is the ordinary one. DOCKER_HOST
  # above is colima's macOS-side forwarding socket and does not exist there.
  export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
fi
