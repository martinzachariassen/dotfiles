#!/usr/bin/env bats
#
# modules/swift. Xcode, xcode-select and the licence are all system-wide state
# no sandbox can fake for real, so every hook is driven through DOT_XCODE_APP,
# a stubbed xcode-select/defaults and DOT_CODE_BIN -- the same trick
# DOT_OP_SSH_SIGN and DOT_CODE_BIN already use in modules/git.

load helper

setup() {
  setup_sandbox
  STUB="$DOT_TMP/bin"
  mkdir -p "$STUB"
  XCODE="$DOT_TMP/Xcode.app"
  EXT_DIR="$DOT_TMP/vscode-extensions"
  mkdir -p "$EXT_DIR"
}

teardown() { teardown_sandbox; }

# fake_xcode VERSION -- an Xcode.app with just enough of Info.plist for the
# licence check's `defaults read` to answer.
fake_xcode() {
  mkdir -p "$XCODE/Contents"
  cat >"$XCODE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>${1:-16.0}</string>
</dict>
</plist>
EOF
}

# stub_tools SELECTED_DIR AGREED_VERSION -- xcode-select and defaults, real
# tools that read system-wide and /Library state this sandbox cannot fake.
stub_tools() {
  local selected=$1 agreed=$2
  cat >"$STUB/xcode-select" <<EOF
#!/usr/bin/env bash
[ "\$1" = "-p" ] && printf '%s\n' "$selected"
EOF
  chmod +x "$STUB/xcode-select"

  cat >"$STUB/defaults" <<EOF
#!/usr/bin/env bash
case "\$3" in
  IDEXcodeVersionForAgreedToGMLicense) printf '%s\n' "$agreed" ;;
  CFBundleShortVersionString) /usr/bin/defaults read "\$2" "\$3" ;;
esac
EOF
  chmod +x "$STUB/defaults"
}

doctor() {
  run env PATH="$STUB:$PATH" HOME="$HOME" DOT_ROOT="$DOT_ROOT" \
    DOT_MODULE=swift DOT_MODULE_DIR="$DOT_ROOT/modules/swift" \
    DOT_XCODE_APP="${1-$XCODE}" DOT_CODE_BIN="${2-$STUB/code}" \
    DOT_VSCODE_EXT_DIR="${3-$EXT_DIR}" \
    "$BASH" "$DOT_ROOT/modules/swift/doctor.sh"
}

apply() {
  run env PATH="$STUB:$PATH" HOME="$HOME" DOT_ROOT="$DOT_ROOT" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN="${1:-0}" \
    DOT_MODULE=swift DOT_MODULE_DIR="$DOT_ROOT/modules/swift" \
    DOT_CODE_BIN="${2-$STUB/code}" \
    "$BASH" "$DOT_ROOT/modules/swift/apply.sh"
}

remove() {
  run env HOME="$HOME" DOT_ROOT="$DOT_ROOT" \
    DOT_MODULE=swift DOT_MODULE_DIR="$DOT_ROOT/modules/swift" \
    DOT_VSCODE_EXT_DIR="${1-$EXT_DIR}" \
    "$BASH" "$DOT_ROOT/modules/swift/remove.sh"
}

# --- doctor.sh: Xcode ---------------------------------------------------------

@test "doctor: Xcode not installed fails and names the fix" {
  doctor "$DOT_TMP/no-such-xcode"
  [ "$status" -eq 1 ]
  says xcode 'not installed -- sign into the App Store, then: dot apply'
}

@test "doctor: Xcode installed and selected, licence accepted, is all green" {
  fake_xcode 16.0
  stub_tools "$XCODE/Contents/Developer" 16.0

  doctor
  says xcode 'selected as the active developer directory'
  says xcode 'licence accepted'
}

@test "doctor: Xcode installed but the Command Line Tools are still active" {
  fake_xcode 16.0
  stub_tools /Library/Developer/CommandLineTools 16.0

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  says xcode 'installed, but the Command Line Tools are still selected'
  [[ $output == *"sudo xcode-select -s $XCODE/Contents/Developer"* ]]
}

@test "doctor: an unaccepted licence names the exact command" {
  fake_xcode 16.0
  stub_tools "$XCODE/Contents/Developer" ''

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  says xcode 'licence not accepted (or Xcode updated since)'
  [[ $output == *"sudo xcodebuild -license accept"* ]]
}

# --- doctor.sh: the VS Code extension -----------------------------------------

@test "doctor: VS Code not installed skips the extension check quietly" {
  fake_xcode 16.0
  stub_tools "$XCODE/Contents/Developer" 16.0

  doctor "$XCODE" "$DOT_TMP/not-installed"
  says vscode 'not installed -- the Swift extension was skipped'
}

@test "doctor: the extension present is read from the install tree" {
  fake_xcode 16.0
  stub_tools "$XCODE/Contents/Developer" 16.0
  mkdir -p "$EXT_DIR/sswg.swift-lang-1.2.3"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB/code"
  chmod +x "$STUB/code"

  doctor
  says vscode 'Swift extension installed'
}

@test "doctor: the extension missing says to apply, without invoking code" {
  # code --list-extensions CREATES ~/.vscode and ~/Library/Application
  # Support/Code on a machine that has neither -- a stub that records any call
  # proves the hook never runs it (dev-cli's mise stub is the same trick).
  fake_xcode 16.0
  stub_tools "$XCODE/Contents/Developer" 16.0
  ran="$DOT_TMP/code_ran"
  cat >"$STUB/code" <<EOF
#!/usr/bin/env bash
echo "code \$*" >>"$ran"
exit 0
EOF
  chmod +x "$STUB/code"

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  says vscode 'Swift extension not installed -- run: dot apply'
  [ ! -f "$ran" ]
}

# --- apply.sh ------------------------------------------------------------------

@test "apply: a dry run announces the extension and changes nothing" {
  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB/code"
  chmod +x "$STUB/code"
  local before
  before=$(home_snapshot)

  apply 1
  [ "$status" -eq 0 ]
  [[ $output == *"install extension sswg.swift-lang"* ]]
  [ "$(home_snapshot)" = "$before" ]
}

@test "apply: VS Code absent skips the extension, without failing" {
  apply 0 "$DOT_TMP/not-installed"
  [ "$status" -eq 0 ]
  says vscode 'VS Code is not installed -- skipping the Swift extension'
}

@test "apply: VS Code present installs the extension" {
  ran="$DOT_TMP/code_ran"
  cat >"$STUB/code" <<EOF
#!/usr/bin/env bash
echo "code \$*" >>"$ran"
exit 0
EOF
  chmod +x "$STUB/code"

  apply
  [ "$status" -eq 0 ]
  says vscode 'extension sswg.swift-lang installed'
  [[ $(cat "$ran") == *"--install-extension sswg.swift-lang"* ]]
}

@test "apply: a failing install is a warning, not a crash" {
  printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB/code"
  chmod +x "$STUB/code"

  apply
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  says vscode 'could not install extension sswg.swift-lang'
}

# --- remove.sh -------------------------------------------------------------

@test "remove: nothing installed says nothing" {
  remove
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remove: the extension is reported, not deleted" {
  mkdir -p "$EXT_DIR/sswg.swift-lang-1.2.3"

  remove
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  says 'left alone' 'the VS Code Swift extension (sswg.swift-lang)'
  [[ $output == *"code --uninstall-extension sswg.swift-lang"* ]]
  [ -d "$EXT_DIR/sswg.swift-lang-1.2.3" ]
}
