alias ls='eza --group-directories-first'
alias ll='eza -l --group-directories-first --git'
alias la='eza -la --group-directories-first --git'
alias tree='eza --tree'
alias cat='bat --paging=never'
alias grep='rg'

alias g='git'
alias gs='git status --short --branch'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'

alias ..='cd ..'
alias ...='cd ../..'

# Plain `exec zsh` inherits ZDOTDIR and silently skips ~/.zshenv.
alias reload='exec env -u ZDOTDIR zsh -l'
