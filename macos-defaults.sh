#!/usr/bin/env bash
# macos-defaults.sh — opinionated macOS system defaults
# Run manually:  bash ~/Dev/Personal/dotfiles/macos-defaults.sh
# Or applied automatically by chezmoi via .chezmoiscripts/run_onchange_after_*.sh
#
# Safe to re-run. Some changes need a logout/restart to take full effect.
# Each `defaults write` is annotated; comment out anything you don't want.

set -euo pipefail
echo "Applying macOS defaults — sudo will be requested for some changes."
sudo -v

# Keep sudo alive while this script runs
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

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
            case "$value" in true|YES|yes|1) want=1 ;; *) want=0 ;; esac
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
def_write NSGlobalDomain ApplePressAndHoldEnabled               -bool false   # disable accents-on-hold; lets you hold j/k in vim
def_write NSGlobalDomain KeyRepeat                              -int 2        # min 2 (≈30ms)
def_write NSGlobalDomain InitialKeyRepeat                       -int 15       # min 15 (≈225ms)
def_write NSGlobalDomain NSAutomaticCapitalizationEnabled       -bool false
def_write NSGlobalDomain NSAutomaticDashSubstitutionEnabled     -bool false
def_write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled   -bool false
def_write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled    -bool false
def_write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled   -bool false
def_write NSGlobalDomain AppleKeyboardUIMode                    -int 3        # full keyboard access (Tab through dialogs)

# ═══════════════════════════════════════════════════════════════════════════════
# TRACKPAD
# ═══════════════════════════════════════════════════════════════════════════════
def_write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1   # -currentHost can't go through the helper
def_write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
# Three-finger drag (uncomment to enable)
# defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true

# ═══════════════════════════════════════════════════════════════════════════════
# FINDER — show everything; default to list view; sane sidebar
# ═══════════════════════════════════════════════════════════════════════════════
def_write NSGlobalDomain AppleShowAllExtensions      -bool   true              # show all file extensions
def_write com.apple.finder AppleShowAllFiles         -bool   true              # show hidden files (Cmd+Shift+. still toggles)
def_write com.apple.finder ShowPathbar               -bool   true
def_write com.apple.finder ShowStatusBar             -bool   true
def_write com.apple.finder _FXShowPosixPathInTitle   -bool   true              # full POSIX path in window title
def_write com.apple.finder FXPreferredViewStyle      -string "Nlsv"            # list view
def_write com.apple.finder FXDefaultSearchScope      -string "SCcf"            # search current folder, not whole Mac
def_write com.apple.finder FXEnableExtensionChangeWarning -bool false
def_write com.apple.finder WarnOnEmptyTrash          -bool   false
def_write com.apple.finder NewWindowTarget           -string "PfHm"            # new window opens to ~
def_write com.apple.finder NewWindowTargetPath       -string "file://${HOME}/"

# Stop creating .DS_Store on network and USB volumes
def_write com.apple.desktopservices DSDontWriteNetworkStores -bool true
def_write com.apple.desktopservices DSDontWriteUSBStores     -bool true

# Show ~/Library (Apple hides it by default)
chflags nohidden "${HOME}/Library" 2>/dev/null || true

# Show /Volumes
sudo chflags nohidden /Volumes 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════════
# DOCK — small, auto-hide, no recent apps, no animation lag
# ═══════════════════════════════════════════════════════════════════════════════
def_write com.apple.dock tilesize                -int    42
def_write com.apple.dock autohide                -bool   true
def_write com.apple.dock autohide-delay          -float  0                      # no delay before showing
def_write com.apple.dock autohide-time-modifier  -float  0.4                    # faster show/hide animation
def_write com.apple.dock show-recents            -bool   false                  # no recent apps section
def_write com.apple.dock mineffect               -string "scale"                # minimize: scale (faster) instead of genie
def_write com.apple.dock mru-spaces              -bool   false                  # don't reorder spaces by recent use
def_write com.apple.dock expose-group-by-app     -bool   false                  # Mission Control: don't group windows by app

# ═══════════════════════════════════════════════════════════════════════════════
# SCREENSHOTS — save to ~/Pictures/Screenshots, no shadow, PNG
# ═══════════════════════════════════════════════════════════════════════════════
mkdir -p "${HOME}/Pictures/Screenshots"
def_write com.apple.screencapture location       -string "${HOME}/Pictures/Screenshots"
def_write com.apple.screencapture type           -string "png"
def_write com.apple.screencapture disable-shadow -bool   true
def_write com.apple.screencapture include-date   -bool   true

# ═══════════════════════════════════════════════════════════════════════════════
# SAFARI — dev menu, full URL, no auto-open downloads
# ═══════════════════════════════════════════════════════════════════════════════
# NOTE: Safari is sandboxed on modern macOS. These writes only succeed if your
# terminal app (Ghostty/Terminal/iTerm) has Full Disk Access in
# System Settings → Privacy & Security → Full Disk Access.
# We swallow errors here so the rest of the script still runs without it.
{
    defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
    defaults write com.apple.Safari IncludeDevelopMenu -bool true
    defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
    defaults write com.apple.Safari "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" -bool true
    defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
} 2>/dev/null || echo "  ⚠️  Safari defaults skipped — grant your terminal Full Disk Access if you want them applied."

# ═══════════════════════════════════════════════════════════════════════════════
# TEXTEDIT — plain text default, UTF-8
# ═══════════════════════════════════════════════════════════════════════════════
{
    defaults write com.apple.TextEdit RichText -int 0
    defaults write com.apple.TextEdit PlainTextEncoding -int 4
    defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
} 2>/dev/null || echo "  ⚠️  TextEdit defaults skipped (sandbox)."

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
# Apply changes — restart affected apps only if their settings actually changed
# ═══════════════════════════════════════════════════════════════════════════════
restart_if_changed() {
    local app="$1" ; shift
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
restart_if_changed Finder         com.apple.finder com.apple.desktopservices
restart_if_changed Dock           com.apple.dock
restart_if_changed SystemUIServer com.apple.screencapture com.apple.systemuiserver

echo "Done. ${#CHANGED_DOMAINS[@]} write(s) applied. Some changes (keyboard repeat, screenshot location) may need a logout to take full effect."
