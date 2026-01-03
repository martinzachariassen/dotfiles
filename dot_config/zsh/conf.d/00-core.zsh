# History (force correct locations even if macOS defaults interfere)
export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
export ZSH_SESSION_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/sessions"
mkdir -p "$(dirname "$HISTFILE")" "$ZSH_SESSION_DIR" 2>/dev/null

HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS HIST_REDUCE_BLANKS
setopt INC_APPEND_HISTORY SHARE_HISTORY

# Quality-of-life
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS
setopt NO_BEEP
bindkey -e
