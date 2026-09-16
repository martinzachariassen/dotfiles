#!/usr/bin/env bash
#
# Everything else Xcode needs after this -- accepting its licence, pointing
# xcode-select at it -- takes sudo, which module hooks never do (root
# CLAUDE.md). Those stay a one-time manual step; doctor.sh names the command.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# Same literal as doctor.sh and remove.sh (tests/contract.bats).
ext=sswg.swift-lang

# Absolute, like DOT_CODE_BIN in modules/git: only written when VS Code is
# installed (the apps module), or a machine without it would fail every run.
code=${DOT_CODE_BIN:-/opt/homebrew/bin/code}
xcode=${DOT_XCODE_APP:-/Applications/Xcode.app}

if [[ -x $code ]]; then
  if [[ $DOT_DRY_RUN == 1 ]]; then
    info vscode "install extension $ext"
  elif "$code" --install-extension "$ext" >/dev/null 2>&1; then
    ok vscode "extension $ext installed"
  else
    warn vscode "could not install extension $ext"
  fi
else
  dim vscode 'VS Code is not installed -- skipping the Swift extension'
fi

# --- simulator runtimes (settings.swift.simulators) --------------------------
#
# Names as they read in `xcrun simctl list runtimes`, e.g. "iOS 17.4" -- not
# installed unless asked for, because each one is a multi-gigabyte download.

mapfile -t simulators < <(module_setting_list swift simulators)

if ((${#simulators[@]})); then
  developer_dir=$(xcode-select -p 2>/dev/null || true)
  if [[ $developer_dir != "$xcode/Contents/Developer" ]]; then
    dim simulators 'skipped -- Xcode is not the selected developer directory yet'
  else
    # simctl's own state lives under ~/Library/Developer/CoreSimulator, which
    # home_snapshot prunes (tests/helper.bash) -- reading it here carries the
    # same guarantee as doctor.sh's `defaults read` calls.
    installed=$(xcrun simctl list runtimes 2>/dev/null || true)
    for name in "${simulators[@]}"; do
      if grep -qF "$name" <<<"$installed"; then
        ok simulator "$name already installed"
      elif [[ $DOT_DRY_RUN == 1 ]]; then
        info simulator "install $name"
      elif xcodes runtimes install "$name" >/dev/null 2>&1; then
        ok simulator "$name installed"
      else
        # xcodes' runtime catalog, not xcodebuild -downloadPlatform: the
        # latter only ever offers what is current for the installed Xcode. A
        # failed install is a warning, not a failure -- a multi-gigabyte
        # download over flaky network earns a retry, not a red exit status
        # that hides everything else this run did.
        warn simulator "could not install $name -- retry: xcodes runtimes install \"$name\""
      fi
    done
  fi
fi
