# chezup.tape — records the `chezup` converge flow for the README.
#
# Runs the real scripts/chezup.sh against a throwaway sandbox (see sandbox.sh)
# with a neutral prompt, so the clip shows the genuine three-phase flow without
# reflecting any real terminal, prompt, paths, or config. DRY_RUN=1 means pull
# and apply are printed, never executed.
#
# Regenerate:  vhs assets/tapes/chezup.tape   (needs vhs: brew install vhs)

Output "assets/demo-chezup.gif"

Set Shell "zsh"
Set FontSize 13
Set Width 760
Set Height 640
Set Theme "Catppuccin Frappe"
Set Padding 12
Set Framerate 24
Set TypingSpeed 50ms

# ── Hidden setup: isolated sandbox + neutral prompt ──────────────────────────
Hide
Type "export REPO=$PWD"
Enter
Type "export HOME=/tmp/dotfiles-demo"
Enter
Type "export DOTFILES_DIR=$HOME/dotfiles"
Enter
Type "export XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache"
Enter
Type "unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM STARSHIP_CONFIG"
Enter
Type "export PROMPT='%F{magenta}❯%f '"
Enter
Type "bash $REPO/assets/tapes/sandbox.sh"
Enter
Type 'chezup() { DRY_RUN=1 bash $REPO/scripts/chezup.sh "$@"; }'
Enter
Type "cd $HOME"
Enter
Type "clear"
Enter
Show
Sleep 700ms

# ── Run the everyday command ─────────────────────────────────────────────────
Type "chezup"
Sleep 600ms
Enter

# Phase 1 (pull) + Phase 2 (review pending drift)
Sleep 4s

# "Apply these N change(s)?" — accept the default (Yes)
Enter

# Phase 3 (dry-run apply) + done card
Sleep 3500ms
