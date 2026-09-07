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
# Colima's socket isn't Docker's default unix:///var/run/docker.sock; the
# `docker` CLI finds it through the context colima registers, but
# Testcontainers doesn't read that context and fails claiming Docker is
# unreachable unless DOCKER_HOST names the socket directly.
if [[ -d "$HOME/.colima/default" ]]; then
  export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"

  # Testcontainers bind-mounts this path into its Ryuk reaper container to
  # reach Docker. The mount source has to resolve INSIDE the colima VM, where
  # dockerd's own socket is the ordinary /var/run/docker.sock -- DOCKER_HOST
  # above is colima's macOS-side forwarding socket and does not exist there.
  export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
fi
