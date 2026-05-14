# Uninstall / reset

For the supported "make Homebrew match the managed workstation set" flow, run:

```sh
bash ~/Dev/Personal/dotfiles/install.sh --mirror-brew
bash ~/Dev/Personal/dotfiles/install.sh --reset-brew
```

`--mirror-brew` leaves the Homebrew installation in place and removes formulae/casks that are not listed in the active Brewfile set for your selected profile/features. `--reset-brew` removes all current formulae/casks first, then reinstalls whatever the selected profile/features require. Both are intentionally guarded by an explicit confirmation phrase in interactive mode.

There's no `uninstall.sh` because there's not a clean inverse — the bootstrap installs ~55 brew packages, modifies macOS defaults, and changes your shell's interpretation of `$HOME`. If you want to walk it back, the steps are:

```sh
# 1. Stop chezmoi managing your $HOME (drops the source link, leaves $HOME files in place).
chezmoi purge                                                # interactive; removes ~/.config/chezmoi/

# 2. Remove every brew package this repo installed. The two-step form below
#    keeps tools you've added on top.
brew bundle cleanup --force --file=~/Dev/Personal/dotfiles/Brewfile
brew bundle cleanup --force --file=~/Dev/Personal/dotfiles/brewfiles/Brewfile.personal
brew bundle cleanup --force --file=~/Dev/Personal/dotfiles/brewfiles/Brewfile.work

# 3. Restore from the pre-install backup (install.sh writes one before its first apply).
ls ~/.dotfiles-backup-*                                      # find the snapshot
cp -r ~/.dotfiles-backup-<timestamp>/. ~/                    # restore

# 4. Remove the source repo if you don't want to keep it.
rm -rf ~/Dev/Personal/dotfiles
```

macOS system defaults applied by `scripts/macos-defaults.sh` aren't reverted by the above — they're sticky settings you'd toggle back via *System Settings* (or by writing inverse `defaults write` commands). The Touch ID for sudo line in `/etc/pam.d/sudo_local` can be removed with `sudo rm /etc/pam.d/sudo_local` (keeps Apple's `sudo_local.template` intact).

The `~/.dotfiles-backup-*` directories accumulate — one per install run. After verifying you don't need them, `rm -rf ~/.dotfiles-backup-*`.
