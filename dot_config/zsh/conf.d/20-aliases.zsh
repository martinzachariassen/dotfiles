command -v rg  >/dev/null && alias grep='rg'
command -v eza >/dev/null && alias ls='eza' && alias ll='eza -lah' && alias la='eza -la'
command -v bat >/dev/null && alias cat='bat -p'

alias g='git'
alias gs='git status'
alias gl='git log --oneline --decorate --graph'
alias gd='git diff'
alias n='nvim'

command -v delta >/dev/null && export GIT_PAGER='delta'
