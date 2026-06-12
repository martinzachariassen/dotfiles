# wizard.tape — records the install.sh bootstrap wizard for the README.
#
# Runs the real installer with DRY_RUN=1 (every state-changing command is
# printed, never executed) under a throwaway $HOME, so it shows the genuine
# fresh-Mac experience with no personal data. The run is aborted at the final
# "Proceed?" prompt — nothing is installed, removed, or written.
#
# Regenerate:  vhs assets/tapes/wizard.tape   (needs vhs: brew install vhs)

Output "assets/demo-wizard.gif"

Set Shell "zsh"
Set FontSize 15
Set Width 1080
Set Height 1000
Set Theme "Catppuccin Frappe"
Set Padding 18
Set TypingSpeed 55ms
Set PlaybackSpeed 1.0

# ── Hidden setup: clean prompt + throwaway HOME ──────────────────────────────
Hide
Type "export PROMPT='%F{magenta}❯%f '"
Enter
Type "export HOME=$(mktemp -d /tmp/dotfiles-wizard.XXXXXX)"
Enter
Type "export XDG_CONFIG_HOME=$HOME/.config"
Enter
Type "unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM"
Enter
Type "cd /Users/martin/Developer/personal/dotfiles"
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

# Probe → "Choose setup": Profile menu (keep default)
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

# Setup style → keep "Continue with recommended setup"
Sleep 1800ms
Enter

# Review plan → "Proceed with installation?" — decline (down to No, Enter)
Sleep 2500ms
Down
Sleep 700ms
Enter

# Let the clean abort render
Sleep 3s
