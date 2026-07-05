#!/usr/bin/env bash
# macos-defaults.sh — opinionated macOS system defaults
# Run manually:  bash ~/Developer/personal/dotfiles/scripts/bin/macos-defaults.sh
# Or applied automatically by chezmoi via .chezmoiscripts/run_once_after_*.sh
#
# Safe to re-run. Some changes need a logout/restart to take full effect.
# Each `defaults write` is annotated; comment out anything you don't want.

set -euo pipefail

# Shared glyphs + status printers from lib/ (one level up: this lives under
# bin/), so the banner/status marks fall back to ASCII on a non-UTF-8 locale
# instead of printing mojibake. log.sh is a committed sibling; fail loudly if a
# checkout is missing it.
_MD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$_MD_DIR/../lib/log.sh" ]; then
    printf 'macos-defaults: missing %s\n' "$_MD_DIR/../lib/log.sh" >&2
    exit 1
fi
# shellcheck source=../lib/log.sh
. "$_MD_DIR/../lib/log.sh"
ui_init_status

printf '%s macOS defaults\n' "$NODE"
echo "  Applying Finder, Dock, keyboard, screenshots, security, and developer preferences."

# When this script runs as part of `chezmoi apply`, the run_before_00-sudo-cache
# script already prompted upfront and cached the credentials; sudo -v here is a
# silent no-op. When it runs standalone (via the `macos-defaults` zsh alias) the
# cache may be empty, in which case we prompt.
#
# Defensive against the "first keystroke eaten by TTY mode race" some
# GPU-accelerated terminals (Ghostty, Alacritty, Kitty) exhibit:
#   • Brief sleep so any pending terminal output is fully drained before
#     sudo flips the line discipline to no-echo.
#   • A distinct -p prompt so the user has an unambiguous visual signal
#     this is the sudo password, not some other interactive question.
if ! sudo -n true 2>/dev/null; then
    sleep 0.2
fi
sudo -v -p "[macos-defaults] sudo password: "

# Keep sudo alive while this script runs. Double-forked + tight poll so the
# keeper exits within 2s of this script — same reasoning as the chezmoi
# pre-auth script's keeper. Without this, you'd see a perceived shell "halt"
# at the end of `macos-defaults` while waiting for the keeper to notice.
PARENT_PID=$$
(
    (
        refresh_in=0
        while kill -0 "$PARENT_PID" 2>/dev/null; do
            if [ "$refresh_in" -le 0 ]; then
                sudo -n true 2>/dev/null || exit
                refresh_in=240
            fi
            sleep 2
            refresh_in=$((refresh_in - 2))
        done
    ) &
) </dev/null >/dev/null 2>&1

# def_write <domain> <key> <-type> <value>
# Reads the current value first and only writes when it differs. Cuts re-apply
# time noticeably when the chezmoi run_onchange_after_* trigger fires after a
# small edit, since most settings are already correct.
CHANGED_DOMAINS=()
def_write() {
    local domain="$1" key="$2" type="$3" value="$4"
    local current
    current=$(defaults read "$domain" "$key" 2>/dev/null || true)
    # `defaults read` returns 0/1 for bools, the raw string/int otherwise.
    # Normalize the value the same way before comparing.
    local want
    case "$type" in
        -bool)
            case "$value" in true | YES | yes | 1) want=1 ;; *) want=0 ;; esac
            ;;
        *) want="$value" ;;
    esac
    if [[ "$current" != "$want" ]]; then
        defaults write "$domain" "$key" "$type" "$value"
        CHANGED_DOMAINS+=("$domain")
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# KEYBOARD & INPUT — fastest possible key repeat, disable annoying autocorrect
# ═══════════════════════════════════════════════════════════════════════════════
def_write NSGlobalDomain ApplePressAndHoldEnabled -bool false # disable accents-on-hold; lets you hold j/k in vim
def_write NSGlobalDomain KeyRepeat -int 2                     # min 2 (≈30ms)
def_write NSGlobalDomain InitialKeyRepeat -int 15             # min 15 (≈225ms)
def_write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
def_write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
def_write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
def_write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
def_write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
def_write NSGlobalDomain AppleKeyboardUIMode -int 3                    # full keyboard access (Tab through dialogs)
def_write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true # expanded save panels
def_write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
def_write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true # expanded print panels
def_write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# ═══════════════════════════════════════════════════════════════════════════════
# TRACKPAD
# ═══════════════════════════════════════════════════════════════════════════════
def_write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1 # -currentHost can't go through the helper
def_write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
# Three-finger drag (uncomment to enable)
# defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true

# ═══════════════════════════════════════════════════════════════════════════════
# FINDER — show everything; default to list view; sane sidebar
# ═══════════════════════════════════════════════════════════════════════════════
def_write NSGlobalDomain AppleShowAllExtensions -bool true # show all file extensions
def_write com.apple.finder AppleShowAllFiles -bool true    # show hidden files (Cmd+Shift+. still toggles)
def_write com.apple.finder ShowPathbar -bool true
def_write com.apple.finder ShowStatusBar -bool true
def_write com.apple.finder _FXShowPosixPathInTitle -bool true  # full POSIX path in window title
def_write com.apple.finder FXPreferredViewStyle -string "Nlsv" # list view
def_write com.apple.finder FXDefaultSearchScope -string "SCcf" # search current folder, not whole Mac
def_write com.apple.finder FXEnableExtensionChangeWarning -bool false
def_write com.apple.finder WarnOnEmptyTrash -bool false
def_write com.apple.finder NewWindowTarget -string "PfHm" # new window opens to ~
def_write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"
def_write com.apple.finder QuitMenuItem -bool true          # enable Cmd+Q / Finder → Quit Finder
def_write com.apple.finder _FXSortFoldersFirst -bool true   # keep folders on top when sorting by name
def_write com.apple.finder FXRemoveOldTrashItems -bool true # auto-remove trashed items after 30 days

# Stop creating .DS_Store on network and USB volumes
def_write com.apple.desktopservices DSDontWriteNetworkStores -bool true
def_write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Show ~/Library (Apple hides it by default)
chflags nohidden "${HOME}/Library" 2>/dev/null || true

# Show /Volumes
sudo chflags nohidden /Volumes 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════════
# DOCK — small, auto-hide, no recent apps, no animation lag
# ═══════════════════════════════════════════════════════════════════════════════
def_write com.apple.dock tilesize -int 42
def_write com.apple.dock autohide -bool true
def_write com.apple.dock autohide-delay -float 0              # no delay before showing
def_write com.apple.dock autohide-time-modifier -float 0.4    # faster show/hide animation
def_write com.apple.dock show-recents -bool false             # no recent apps section
def_write com.apple.dock mineffect -string "scale"            # minimize: scale (faster) instead of genie
def_write com.apple.dock mru-spaces -bool false               # don't reorder spaces by recent use
def_write com.apple.dock expose-group-by-app -bool false      # Mission Control: don't group windows by app
def_write com.apple.dock minimize-to-application -bool true   # minimize windows into the app icon, not the Dock's right side
def_write com.apple.dock showhidden -bool true                # translucent Dock icons for hidden apps (Cmd+H)
def_write com.apple.dock expose-animation-duration -float 0.1 # faster Mission Control animation

# ═══════════════════════════════════════════════════════════════════════════════
# SCREENSHOTS — save to ~/Pictures/Screenshots, no shadow, PNG
# ═══════════════════════════════════════════════════════════════════════════════
mkdir -p "${HOME}/Pictures/Screenshots"
def_write com.apple.screencapture location -string "${HOME}/Pictures/Screenshots"
def_write com.apple.screencapture type -string "png"
def_write com.apple.screencapture disable-shadow -bool true
def_write com.apple.screencapture include-date -bool true
def_write com.apple.screencapture show-thumbnail -bool false # skip the floating thumbnail — file lands immediately

# ═══════════════════════════════════════════════════════════════════════════════
# WINDOWS & DOCUMENTS (global) — snappier windows, save locally by default
# ═══════════════════════════════════════════════════════════════════════════════
def_write NSGlobalDomain NSWindowResizeTime -float 0.001               # near-instant window resize animation
def_write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false # default Save target is the local disk, not iCloud

# ═══════════════════════════════════════════════════════════════════════════════
# TEXTEDIT — plain text default, UTF-8
# ═══════════════════════════════════════════════════════════════════════════════
{
    defaults write com.apple.TextEdit RichText -int 0
    defaults write com.apple.TextEdit PlainTextEncoding -int 4
    defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
} 2>/dev/null || s_warn "TextEdit defaults skipped (sandbox)."

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY & PRIVACY
# ═══════════════════════════════════════════════════════════════════════════════
# Require password immediately after sleep / screensaver
# (These keys moved to a Lock Screen pane in newer macOS — writes may be silently
# ignored, but they don't error.)
defaults write com.apple.screensaver askForPassword -int 1 2>/dev/null || true
defaults write com.apple.screensaver askForPasswordDelay -int 0 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════════
# DEVELOPMENT NICETIES
# ═══════════════════════════════════════════════════════════════════════════════
# Show build duration in Xcode title bar (sandboxed if Xcode isn't installed)
defaults write com.apple.dt.Xcode ShowBuildOperationDuration -bool true 2>/dev/null || true

# Subpixel font rendering on non-Apple LCDs (cosmetic; no effect on Retina)
def_write NSGlobalDomain AppleFontSmoothing -int 1

# Disable shake-mouse-to-find-cursor (annoying when you actually want a tiny cursor).
# Comment out if you LIKE this feature.
def_write NSGlobalDomain CGDisableCursorLocationMagnification -bool true

# ═══════════════════════════════════════════════════════════════════════════════
# TOUCH ID FOR SUDO (Sonoma 14+)
# ═══════════════════════════════════════════════════════════════════════════════
# Lets you authenticate `sudo` with Touch ID instead of typing the password.
# Apple introduced /etc/pam.d/sudo_local in Sonoma specifically to make this
# survive OS upgrades — earlier macOS versions required editing the protected
# /etc/pam.d/sudo, which got reverted on every system update. We write the
# upgrade-stable file.
#
# Skipped on pre-Sonoma. Skipped if the line is already present. Single
# `sudo tee` so we don't read the file (which is owned by root).
SUDO_LOCAL=/etc/pam.d/sudo_local
SUDO_LOCAL_TEMPLATE=/etc/pam.d/sudo_local.template
macos_major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$macos_major" -ge 14 ]; then
    if sudo grep -q "pam_tid.so" "$SUDO_LOCAL" 2>/dev/null; then
        : # already configured
    else
        # Apple ships a sudo_local.template you're meant to copy + edit.
        # Build it if missing so we don't depend on the template's existence.
        if [ -r "$SUDO_LOCAL_TEMPLATE" ] && ! sudo test -f "$SUDO_LOCAL"; then
            sudo cp "$SUDO_LOCAL_TEMPLATE" "$SUDO_LOCAL"
        fi
        printf '# Managed by dotfiles macos-defaults.sh\nauth       sufficient     pam_tid.so\n' |
            sudo tee -a "$SUDO_LOCAL" >/dev/null
        s_pass "Touch ID for sudo enabled"
    fi
else
    s_warn "Touch ID for sudo skipped — requires macOS Sonoma (14+)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Apply changes — restart affected apps only if their settings actually changed
# ═══════════════════════════════════════════════════════════════════════════════
restart_if_changed() {
    local app="$1"
    shift
    # bash 3.2 (macOS default) has a known bug with `${arr[@]:-}` under set -u;
    # explicit length check sidesteps it.
    [[ ${#CHANGED_DOMAINS[@]} -eq 0 ]] && return
    local changed domain
    for changed in "${CHANGED_DOMAINS[@]}"; do
        for domain in "$@"; do
            if [[ "$changed" == "$domain" ]]; then
                killall "$app" >/dev/null 2>&1 || true
                return
            fi
        done
    done
}
restart_if_changed Finder com.apple.finder com.apple.desktopservices
restart_if_changed Dock com.apple.dock
restart_if_changed SystemUIServer com.apple.screencapture com.apple.systemuiserver

printf '%s%s%s macOS defaults complete — %d write(s) applied\n' \
    "$GREEN" "$OK_MARK" "$RESET" "${#CHANGED_DOMAINS[@]}"
echo "  A logout or reboot may be needed for keyboard repeat and screenshot changes."
