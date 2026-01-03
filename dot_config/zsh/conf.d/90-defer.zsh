# Defer heavier init without using zle-line-init (avoids widget/function collisions).
# Runs once, scheduled right after the first prompt is displayed.

autoload -Uz add-zsh-hook

typeset -ga __zsh_deferred
defer() { __zsh_deferred+=("$*"); }

__run_deferred_once() {
  local cmd
  for cmd in "${__zsh_deferred[@]}"; do
    eval "$cmd"
  done
  __zsh_deferred=()
}

__schedule_deferred_once() {
  # Remove this hook so it runs only once
  add-zsh-hook -d precmd __schedule_deferred_once 2>/dev/null || true

  # Schedule to run ASAP after prompt display
  sched +0 __run_deferred_once
}

add-zsh-hook precmd __schedule_deferred_once

# ---------------- Deferred payload ----------------

# fzf integrations
if [[ -r /opt/homebrew/opt/fzf/shell/key-bindings.zsh ]]; then
  defer 'source /opt/homebrew/opt/fzf/shell/key-bindings.zsh'
  defer 'source /opt/homebrew/opt/fzf/shell/completion.zsh'
fi

# Make fzf fast
defer 'command -v fd >/dev/null && export FZF_DEFAULT_COMMAND="fd --hidden --follow --exclude .git"'
defer 'export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"'

# zoxide: `z <dir>`
defer 'command -v zoxide >/dev/null && eval "$(zoxide init zsh)"'

# atuin: history search (Ctrl-R)

# autosuggestions
if [[ -r /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  defer 'source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh'
fi

# syntax highlighting must be last
if [[ -r /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  defer 'source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
fi


# Defer ZLE widgets/bindings (keeps zsh -ic fast)
defer 'source "$ZDOTDIR/conf.d/70-history-nav.deferred.zsh"'

