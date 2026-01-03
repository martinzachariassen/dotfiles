export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
export STARSHIP_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/starship"

command -v starship >/dev/null && eval "$(starship init zsh)"
