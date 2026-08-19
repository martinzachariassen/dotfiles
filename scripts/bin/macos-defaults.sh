#!/usr/bin/env bash
# macos-defaults.sh — opinionated macOS system defaults. Safe to re-run; some
# changes need a logout/restart to take effect. Also applied by chezmoi.

set -euo pipefail

# log.sh and sudo.sh are committed siblings; fail loudly if a checkout is missing either.
_MD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
for _md_lib in log.sh sudo.sh; do
    if [ ! -r "$_MD_DIR/../lib/$_md_lib" ]; then
        printf 'macos-defaults: missing %s\n' "$_MD_DIR/../lib/$_md_lib" >&2
        exit 1
    fi
done
unset _md_lib
# shellcheck source=../lib/log.sh
. "$_MD_DIR/../lib/log.sh"
# shellcheck source=../lib/sudo.sh
. "$_MD_DIR/../lib/sudo.sh"
ui_init_status

printf '%s macOS defaults\n' "$NODE"
echo "  Applying Finder, Dock, keyboard, screenshots, security, and developer preferences."

# Under chezmoi apply the pre-auth hook already cached creds (no-op here); the
# sleep works around a first-keystroke-eaten TTY race on GPU terminals.
if ! sudo -n true 2>/dev/null; then
    sleep 0.2
fi
sudo -v -p "[macos-defaults] sudo password: "

# Keep sudo alive for the rest of this script — unless a chezmoi apply already
# has run_before_00-sudo-cache's keeper running for the whole apply lifetime
# (DOTFILES_SUDO_KEPT_WARM=1, set by the run_onchange_after_04 hook), in which
# case a second keeper would just be a redundant poller.
if [ "${DOTFILES_SUDO_KEPT_WARM:-0}" != "1" ]; then
    sudo_keep_warm "$$"
fi

# def_write <domain> <key> <-type> <value> — writes only when the value differs,
# so a re-apply skips settings already correct.
CHANGED_DOMAINS=()
def_write() {
    local domain="$1" key="$2" type="$3" value="$4"
    local current
    current=$(defaults read "$domain" "$key" 2>/dev/null || true)
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

# KEYBOARD & INPUT
def_write NSGlobalDomain ApplePressAndHoldEnabled -bool false # so you can hold j/k in vim
def_write NSGlobalDomain KeyRepeat -int 2                     # min 2 (≈30ms)
def_write NSGlobalDomain InitialKeyRepeat -int 15             # min 15 (≈225ms)
def_write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
def_write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
def_write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
def_write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
def_write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
def_write NSGlobalDomain AppleKeyboardUIMode -int 3 # Tab through all dialog controls
def_write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
def_write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
def_write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
def_write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# TRACKPAD
def_write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1 # -currentHost can't go through the helper
def_write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# FINDER
def_write NSGlobalDomain AppleShowAllExtensions -bool true
def_write com.apple.finder AppleShowAllFiles -bool true
def_write com.apple.finder ShowPathbar -bool true
def_write com.apple.finder ShowStatusBar -bool true
def_write com.apple.finder _FXShowPosixPathInTitle -bool true
def_write com.apple.finder FXPreferredViewStyle -string "Nlsv" # list view
def_write com.apple.finder FXDefaultSearchScope -string "SCcf" # search current folder
def_write com.apple.finder FXEnableExtensionChangeWarning -bool false
def_write com.apple.finder WarnOnEmptyTrash -bool false
def_write com.apple.finder NewWindowTarget -string "PfHm" # new window opens to ~
def_write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"
def_write com.apple.finder QuitMenuItem -bool true # enable Cmd+Q to quit Finder
def_write com.apple.finder _FXSortFoldersFirst -bool true
def_write com.apple.finder FXRemoveOldTrashItems -bool true # purge trash after 30 days

def_write com.apple.desktopservices DSDontWriteNetworkStores -bool true # no .DS_Store on network/USB
def_write com.apple.desktopservices DSDontWriteUSBStores -bool true

chflags nohidden "${HOME}/Library" 2>/dev/null || true # Apple hides it by default
sudo chflags nohidden /Volumes 2>/dev/null || true

# DOCK
def_write com.apple.dock tilesize -int 25
def_write com.apple.dock autohide -bool true
def_write com.apple.dock autohide-delay -float 0           # no delay before showing
def_write com.apple.dock autohide-time-modifier -float 0.4 # faster show/hide animation
def_write com.apple.dock show-recents -bool false
def_write com.apple.dock mineffect -string "scale"            # faster than genie
def_write com.apple.dock mru-spaces -bool false               # don't reorder spaces by recent use
def_write com.apple.dock expose-group-by-app -bool false      # don't group Mission Control windows by app
def_write com.apple.dock minimize-to-application -bool true   # minimize into the app icon
def_write com.apple.dock showhidden -bool true                # translucent icons for hidden apps
def_write com.apple.dock expose-animation-duration -float 0.1 # faster Mission Control animation

# SCREENSHOTS
mkdir -p "${HOME}/Pictures/Screenshots"
def_write com.apple.screencapture location -string "${HOME}/Pictures/Screenshots"
def_write com.apple.screencapture type -string "png"
def_write com.apple.screencapture disable-shadow -bool true
def_write com.apple.screencapture include-date -bool true
def_write com.apple.screencapture show-thumbnail -bool false # file lands immediately, no floating thumbnail

# WINDOWS & DOCUMENTS
def_write NSGlobalDomain NSWindowResizeTime -float 0.001               # near-instant resize animation
def_write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false # default Save to local disk, not iCloud

# TEXTEDIT
{
    def_write com.apple.TextEdit RichText -int 0
    def_write com.apple.TextEdit PlainTextEncoding -int 4
    def_write com.apple.TextEdit PlainTextEncodingForWrite -int 4
} 2>/dev/null || s_warn "TextEdit defaults skipped (sandbox)."

# SECURITY & PRIVACY
# These moved to a Lock Screen pane in newer macOS; writes may be silently ignored.
def_write com.apple.screensaver askForPassword -int 1 2>/dev/null || true
def_write com.apple.screensaver askForPasswordDelay -int 0 2>/dev/null || true

# DEVELOPMENT NICETIES
def_write com.apple.dt.Xcode ShowBuildOperationDuration -bool true 2>/dev/null || true

def_write NSGlobalDomain AppleFontSmoothing -int 1 # subpixel AA on non-Retina LCDs

def_write NSGlobalDomain CGDisableCursorLocationMagnification -bool true # no shake-to-find cursor

# TOUCH ID FOR SUDO (Sonoma 14+)
# sudo_local (added in Sonoma) survives OS upgrades; /etc/pam.d/sudo itself got
# reverted on every update. Single `sudo tee` since the file is root-owned.
SUDO_LOCAL=/etc/pam.d/sudo_local
SUDO_LOCAL_TEMPLATE=/etc/pam.d/sudo_local.template
macos_major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$macos_major" -ge 14 ]; then
    if sudo grep -q "pam_tid.so" "$SUDO_LOCAL" 2>/dev/null; then
        :
    else
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

restart_if_changed() {
    local app="$1"
    shift
    # bash 3.2 has a known `${arr[@]:-}` bug under set -u; length check sidesteps it.
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
