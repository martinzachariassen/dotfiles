# Sourced first by .zshrc.

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Where `dot` lives; core/doctor.sh checks for this.
path=("$HOME/.local/bin" $path)

typeset -U path PATH
export PATH
