#!/usr/bin/env bash
#
# Xcode, mas and the CLI tools are Homebrew/mas packages -- they stay, same as
# every other module's (docs/configuration.md). The VS Code extension is the
# only thing this module put somewhere the uninstall sweep cannot see, and
# even that is nothing safe to delete unasked: report it instead.

set -euo pipefail
source "${DOT_ROOT:?}/lib/dot.sh"

# Same literal as apply.sh and doctor.sh (tests/contract.bats).
ext=sswg.swift-lang

ext_dir=${DOT_VSCODE_EXT_DIR:-$HOME/.vscode/extensions}

if compgen -G "$ext_dir/$ext-*" >/dev/null; then
  warn 'left alone' "the VS Code Swift extension ($ext)"
  dim "remove it yourself: code --uninstall-extension $ext"
fi
