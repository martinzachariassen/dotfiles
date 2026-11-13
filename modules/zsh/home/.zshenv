export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"

if [[ -x /opt/homebrew/bin/code ]]; then
  # Without --wait `code` returns at once and git commits an empty message.
  export EDITOR='code --wait'
  export VISUAL="$EDITOR"
fi

if [[ -d "$HOME/.colima/default" ]]; then
  export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"

  # Ryuk mounts this path inside the VM, where colima's forwarded socket
  # does not exist.
  export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
fi
