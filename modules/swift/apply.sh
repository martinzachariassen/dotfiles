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

if [[ $DOT_DRY_RUN == 1 ]]; then
  info vscode "install extension $ext"
  exit 0
fi

if [[ ! -x $code ]]; then
  dim vscode 'VS Code is not installed -- skipping the Swift extension'
  exit 0
fi

if "$code" --install-extension "$ext" >/dev/null 2>&1; then
  ok vscode "extension $ext installed"
else
  warn vscode "could not install extension $ext"
fi
