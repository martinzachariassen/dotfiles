# Interactive shell. Order: path.zsh, aliases.zsh, tools, local.zsh, then
# syntax highlighting last (it wraps the line editor).

HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=50000
SAVEHIST=50000
mkdir -p "${HISTFILE:h}"

setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt EXTENDED_HISTORY

setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS

# -C skips the per-startup security check, the usual reason a shell opens slowly.
autoload -Uz compinit
compinit -C -d "${XDG_STATE_HOME:-$HOME/.local/state}/zsh/zcompdump"

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # case-insensitive
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors ''

bindkey -e
bindkey '^[[A' history-search-backward # Up: search on what you typed
bindkey '^[[B' history-search-forward

source "$ZDOTDIR/path.zsh"
source "$ZDOTDIR/aliases.zsh"

command -v starship >/dev/null && eval "$(starship init zsh)"
command -v zoxide   >/dev/null && eval "$(zoxide init zsh)"
command -v mise     >/dev/null && eval "$(mise activate zsh)"

# $HOMEBREW_PREFIX comes from `brew shellenv` in path.zsh; `$(brew --prefix)`
# is a subprocess per call and cost ~139 ms of startup.
if [[ -r $HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# Machine-local, untracked, overrides everything above.
[[ -r "$ZDOTDIR/local.zsh" ]] && source "$ZDOTDIR/local.zsh"

# Must be last: it wraps the line editor.
if [[ -r $HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
