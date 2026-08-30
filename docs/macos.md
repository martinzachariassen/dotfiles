# macOS defaults

Every system setting this repo changes, grouped by domain. Applied by
[`features/macos/cli.sh`](../features/macos/cli.sh) (how and when it runs:
[features/macos](../features/macos/README.md)) — the
single source of truth — when the `macosDefaults` module is selected. This doc
mirrors the script; if the two disagree, the script wins.

Each `defaults write` is annotated inline, so **to change a setting, edit the
script** and comment out or adjust the line. See
[applying & reverting](#applying--reverting).

## Keyboard & input

| Setting | Value | Effect |
|---|---|---|
| `KeyRepeat` | `2` | Fastest key repeat (≈30 ms) — below the System Settings minimum. |
| `InitialKeyRepeat` | `15` | Shortest delay before repeat kicks in (≈225 ms). |
| `ApplePressAndHoldEnabled` | `false` | Holding a key repeats it instead of showing the accent picker (lets you hold `j`/`k` in vim). |
| `NSAutomaticCapitalizationEnabled` | `false` | No auto-capitalisation. |
| `NSAutomaticDashSubstitutionEnabled` | `false` | No smart dashes. |
| `NSAutomaticPeriodSubstitutionEnabled` | `false` | No double-space → period. |
| `NSAutomaticQuoteSubstitutionEnabled` | `false` | Straight quotes, not curly. |
| `NSAutomaticSpellingCorrectionEnabled` | `false` | No autocorrect. |
| `AppleKeyboardUIMode` | `3` | Full keyboard access — Tab moves through all controls in dialogs. |
| `NSNavPanelExpandedStateForSaveMode[2]` | `true` | Save panels open expanded. |
| `PMPrintingExpandedStateForPrint[2]` | `true` | Print panels open expanded. |

## Trackpad

| Setting | Value | Effect |
|---|---|---|
| `…AppleBluetoothMultitouch.trackpad Clicking` | `true` | Tap to click. |
| `com.apple.mouse.tapBehavior` (global + `-currentHost`) | `1` | Tap-to-click for the login session too. |

Three-finger drag is present but commented out — uncomment in the script to
enable.

## Finder

| Setting | Value | Effect |
|---|---|---|
| `AppleShowAllExtensions` | `true` | Always show file extensions. |
| `AppleShowAllFiles` | `true` | Show hidden dotfiles (`Cmd+Shift+.` still toggles). |
| `ShowPathbar` / `ShowStatusBar` | `true` | Path bar + status bar visible. |
| `_FXShowPosixPathInTitle` | `true` | Full POSIX path in the window title. |
| `FXPreferredViewStyle` | `Nlsv` | Default to list view. |
| `FXDefaultSearchScope` | `SCcf` | Search the current folder, not the whole Mac. |
| `FXEnableExtensionChangeWarning` | `false` | No nag when changing a file extension. |
| `WarnOnEmptyTrash` | `false` | No "are you sure" on empty trash. |
| `NewWindowTarget` / `…Path` | `PfHm` → `~` | New windows open at your home folder. |
| `QuitMenuItem` | `true` | Enables `Cmd+Q` to quit Finder. |
| `_FXSortFoldersFirst` | `true` | Keep folders on top when sorting by name. |
| `FXRemoveOldTrashItems` | `true` | Auto-remove trashed items after 30 days. |
| `DSDontWriteNetworkStores` / `…USBStores` | `true` | Stop writing `.DS_Store` on network + USB volumes. |
| `~/Library` visibility | shown | `chflags nohidden ~/Library`. |
| `/Volumes` visibility | shown | `chflags nohidden /Volumes` (needs sudo). |

## Dock & Mission Control

| Setting | Value | Effect |
|---|---|---|
| `tilesize` | `42` | Smaller Dock icons. |
| `autohide` | `true` | Dock auto-hides. |
| `autohide-delay` | `0` | No delay before it appears. |
| `autohide-time-modifier` | `0.4` | Faster show/hide animation. |
| `show-recents` | `false` | No recent-apps section. |
| `mineffect` | `scale` | Minimise with the faster scale effect, not genie. |
| `mru-spaces` | `false` | Don't auto-reorder Spaces by recent use. |
| `expose-group-by-app` | `false` | Mission Control doesn't group windows by app. |
| `minimize-to-application` | `true` | Minimise windows into the app icon, not the Dock's right side. |
| `showhidden` | `true` | Translucent Dock icons for hidden apps (`Cmd+H`). |
| `expose-animation-duration` | `0.1` | Faster Mission Control animation. |

## Screenshots

| Setting | Value | Effect |
|---|---|---|
| `location` | `~/Pictures/Screenshots` | Save there instead of the Desktop (folder created). |
| `type` | `png` | PNG format. |
| `disable-shadow` | `true` | No drop shadow on window captures. |
| `include-date` | `true` | Timestamp in the filename. |
| `show-thumbnail` | `false` | Skip the floating thumbnail — the file lands immediately. |

## Windows & documents

| Setting | Value | Effect |
|---|---|---|
| `NSWindowResizeTime` | `0.001` | Near-instant window resize animation. |
| `NSDocumentSaveNewDocumentsToCloud` | `false` | Default Save target is the local disk, not iCloud. |

## TextEdit

| Setting | Value | Effect |
|---|---|---|
| `RichText` | `0` | New documents default to plain text. |
| `PlainTextEncoding[ForWrite]` | `4` | UTF-8. |

## Security & privacy

| Setting | Value | Effect |
|---|---|---|
| `askForPassword` | `1` | Require a password after sleep/screensaver. |
| `askForPasswordDelay` | `0` | Require it immediately. |

> These two keys moved to a Lock Screen pane in recent macOS; the writes are
> harmless but may be ignored there. **Touch ID for sudo** is configured
> separately — see below.

## Developer niceties

| Setting | Value | Effect |
|---|---|---|
| `com.apple.dt.Xcode ShowBuildOperationDuration` | `true` | Build time in Xcode's title bar (no-op without Xcode). |
| `AppleFontSmoothing` | `1` | Subpixel smoothing on non-Retina LCDs (cosmetic; no effect on Retina). |
| `CGDisableCursorLocationMagnification` | `true` | Disables shake-to-find-cursor. |

## Touch ID for sudo (Sonoma 14+)

On macOS 14+, the script enables Touch ID for `sudo` by appending
`auth sufficient pam_tid.so` to `/etc/pam.d/sudo_local` — the
**upgrade-stable** file introduced in Sonoma (editing the older
`/etc/pam.d/sudo` got reverted on every OS update). Idempotent (skips if the
line is present) and skipped cleanly on pre-Sonoma.

## Applying & reverting

**How it runs.** The `run_onchange_after_04-macos-defaults` hook (see
[lifecycle.md](lifecycle.md)) applies the script only when the
`macosDefaults` module is selected **and** its *contents change* — the hook
embeds a sha256 of the script, so a routine `chezmoi apply` that didn't touch
it is a no-op with no sudo prompt. Edit the script and the next apply re-runs
it.

**Idempotent + fast.** The `def_write` helper reads each key first and writes
only when the value differs, tracking which domains changed. It then
restarts **only** the affected apps (Finder, Dock, SystemUIServer), so an
unchanged run touches nothing.

**Apply by hand** (after a macOS update reset something, say) without editing
the script:

```sh
macos-defaults          # the zsh alias → features/macos/cli.sh
```

**Revert a setting.** There's no automatic undo — comment the line out in the
script (documents intent, but won't reset an already-applied value), then
reset the live value yourself:

```sh
defaults delete com.apple.dock tilesize        # back to the macOS default
killall Dock                                   # restart the affected app
```

A logout or reboot may be needed for keyboard-repeat and screenshot changes to
fully take effect.
