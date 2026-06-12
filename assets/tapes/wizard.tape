# wizard.tape — records the install.sh bootstrap wizard for the README.
#
# Runs the real installer with DRY_RUN=1 (every state-changing command is
# printed, never executed) from a throwaway sandbox HOME with isolated config,
# so it shows the genuine fresh-Mac experience and reflects no real terminal,
# prompt, paths, or personal data. The run is aborted at the final "Proceed?"
# prompt, so nothing is installed, removed, or written.
#
# Regenerate:  vhs assets/tapes/wizard.tape   (needs vhs: brew install vhs)

Output "assets/demo-wizard.gif"

Set Shell "zsh"
Set FontSize 13
Set Width 840
Set Height 720
Set Theme "Catppuccin Frappe"
Set Padding 12
Set Framerate 24
Set TypingSpeed 50ms

# ── Hidden setup: neutral prompt + isolated sandbox HOME ─────────────────────
Hide
Type "export REPO=$PWD"
Enter
Type "export HOME=/tmp/dotfiles-wizard-demo"
Enter
Type "rm -rf $HOME && mkdir -p $HOME"
Enter
Type "export XDG_CONFIG_HOME=$HOME/.config XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache"
Enter
Type "unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM STARSHIP_CONFIG"
Enter
Type "export PROMPT='%F{magenta}❯%f '"
Enter
Type "cd $REPO"
Enter
Type "clear"
Enter
Show
Sleep 600ms

# ── Launch the wizard (dry-run) ──────────────────────────────────────────────
Type "DRY_RUN=1 bash install.sh"
Sleep 700ms
Enter

# Banner + "Press Enter to begin the setup check"
Sleep 3s
Enter

# Probe -> "Choose setup": Profile menu (keep default)
Sleep 2500ms
Enter

# Full name
Sleep 1200ms
Type "Ada Lovelace"
Sleep 500ms
Enter

# Git email
Sleep 1200ms
Type "ada@example.com"
Sleep 500ms
Enter

# Setup style -> keep "Continue with recommended setup"
Sleep 1800ms
Enter

# Review plan -> "Proceed with installation?" — decline (down to No, Enter)
Sleep 2500ms
Down
Sleep 700ms
Enter

# Let the clean abort render
Sleep 2500ms
