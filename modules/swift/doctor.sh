#!/usr/bin/env bash
#
# Every check mas and xcodebuild themselves would need sudo to fix. This only
# reads state and names the command that closes the gap.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# An input, like DOT_CODE_BIN: a machine without Xcode still has to take the
# "not installed" branch, and mas always installs App Store apps here.
xcode=${DOT_XCODE_APP:-/Applications/Xcode.app}

if [[ ! -d $xcode ]]; then
  fail xcode 'not installed -- sign into the App Store, then: dot apply'
else
  developer_dir=$(xcode-select -p 2>/dev/null || true)
  if [[ $developer_dir == "$xcode/Contents/Developer" ]]; then
    ok xcode 'selected as the active developer directory'
  else
    warn xcode 'installed, but the Command Line Tools are still selected'
    dim "point at it: sudo xcode-select -s $xcode/Contents/Developer"
  fi

  # Both `defaults read` calls: read-only, and never on $HOME -- one plist
  # ships inside Xcode.app, the other is a /Library preference.
  agreed=$(defaults read /Library/Preferences/com.apple.dt.Xcode \
    IDEXcodeVersionForAgreedToGMLicense 2>/dev/null || true)
  current=$(defaults read "$xcode/Contents/Info.plist" \
    CFBundleShortVersionString 2>/dev/null || true)
  if [[ -n $current && $agreed == "$current" ]]; then
    ok xcode 'licence accepted'
  else
    warn xcode 'licence not accepted (or Xcode updated since)'
    dim 'accept it: sudo xcodebuild -license accept'
  fi
fi

# Same literal as apply.sh and remove.sh (tests/contract.bats).
ext=sswg.swift-lang

code=${DOT_CODE_BIN:-/opt/homebrew/bin/code}
ext_dir=${DOT_VSCODE_EXT_DIR:-$HOME/.vscode/extensions}

if [[ -x $code ]]; then
  # The install tree, not `code --list-extensions`: that subcommand creates
  # ~/.vscode and ~/Library/Application Support/Code on a machine that has
  # neither, the same trap `colima status` and `mise ls` set (dev-cli, containers).
  if compgen -G "$ext_dir/$ext-*" >/dev/null; then
    ok vscode 'Swift extension installed'
  else
    warn vscode 'Swift extension not installed -- run: dot apply'
  fi
else
  dim vscode 'not installed -- the Swift extension was skipped'
fi

# --- simulator runtimes (settings.swift.simulators) --------------------------

mapfile -t simulators < <(module_setting_list swift simulators)

if ((${#simulators[@]})); then
  if [[ ! -d $xcode ]] || [[ $developer_dir != "$xcode/Contents/Developer" ]]; then
    dim simulators 'not checked -- Xcode is not the selected developer directory yet'
  else
    # Read-only, and safe on $HOME for the same reason `defaults read` is:
    # simctl's own state lives under ~/Library/Developer/CoreSimulator, which
    # home_snapshot prunes (tests/helper.bash).
    installed=$(xcrun simctl list runtimes 2>/dev/null || true)
    for name in "${simulators[@]}"; do
      if grep -qF "$name" <<<"$installed"; then
        ok simulator "$name installed"
      else
        warn simulator "$name not installed -- run: dot apply"
      fi
    done
  fi
fi
