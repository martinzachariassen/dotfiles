# chezup.tape — records the `chezup` converge flow for the README.
#
# vhs starts a non-login zsh that does not load the managed ~/.config/zsh/.zshrc,
# so we initialise starship for the real prompt and define a thin `chezup`
# wrapper that runs the real scripts/chezup.sh with DRY_RUN=1 (pull is printed,
# apply is printed, nothing is written). The review phase shows genuine pending
# drift from `chezmoi status`.
#
# Regenerate:  vhs assets/tapes/chezup.tape   (needs vhs: brew install vhs)

Output "assets/demo-chezup.gif"

Set Shell "zsh"
Set FontSize 16
Set Width 1080
Set Height 820
Set Theme "Catppuccin Frappe"
Set Padding 18
Set TypingSpeed 60ms

# ── Hidden setup: real prompt + thin DRY_RUN wrapper ─────────────────────────
Hide
Type "export STARSHIP_CONFIG=$HOME/.config/starship.toml"
Enter
Type 'eval "$(starship init zsh)"'
Enter
Type 'chezup() { DRY_RUN=1 bash $HOME/Developer/personal/dotfiles/scripts/chezup.sh "$@"; }'
Enter
Type "cd $HOME/Developer/personal/dotfiles"
Enter
Type "clear"
Enter
Show
Sleep 700ms

# ── Run the everyday command ─────────────────────────────────────────────────
Type "chezup"
Sleep 700ms
Enter

# Phase 1 (pull) + Phase 2 (review pending drift) render
Sleep 4500ms

# "Apply these N change(s)?" — accept the default (Yes)
Enter

# Phase 3 (dry-run apply) + done card
Sleep 3500ms
