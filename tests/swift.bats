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
    DOT_CODE_BIN="${2-$STUB/code}" DOT_XCODE_APP="${3-$XCODE}" \
    "$BASH" "$DOT_ROOT/modules/swift/apply.sh"
}

# write_simulators_config NAME... -- a real config.toml with settings.swift's
# simulators as a TOML array, in the shape module_setting_list actually reads.
write_simulators_config() {
  local quoted=()
  for name in "$@"; do quoted+=("\"$name\""); done
  {
    printf 'schema = 1\n\n'
    printf '[settings.swift]\n'
    printf 'simulators = [%s]\n' "$(
      IFS=,
      printf '%s' "${quoted[*]}"
    )"
  } >"$DOT_CONFIG"
}

# stub_xcrun INSTALLED... -- `xcrun simctl list runtimes` prints one of these
# per line; anything else exits 0 with no output, same as a real machine with
# no matching runtime.
stub_xcrun() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'if [ "$1 $2 $3" = "simctl list runtimes" ]; then\n'
    printf '  cat <<'"'"'RUNTIMES'"'"'\n'
    printf '%s\n' "$@"
    printf 'RUNTIMES\n'
    printf 'fi\n'
  } >"$STUB/xcrun"
  chmod +x "$STUB/xcrun"
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

# --- doctor.sh: simulator runtimes ---------------------------------------------

@test "doctor: no simulators configured says nothing about them" {
  fake_xcode 16.0
  stub_tools "$XCODE/Contents/Developer" 16.0

  doctor
  [[ $output != *simulator* ]]
}

@test "doctor: a configured simulator that is installed is ok" {
  fake_xcode 16.0
  stub_tools "$XCODE/Contents/Developer" 16.0
  write_simulators_config "iOS 17.4"
  stub_xcrun "iOS 17.4 (17.4) - com.apple.CoreSimulator.SimRuntime.iOS-17-4"

  doctor
  says simulator 'iOS 17.4 installed'
}

@test "doctor: a configured simulator that is missing warns" {
  fake_xcode 16.0
  stub_tools "$XCODE/Contents/Developer" 16.0
  write_simulators_config "iOS 17.4"
  stub_xcrun "iOS 16.4 (16.4) - com.apple.CoreSimulator.SimRuntime.iOS-16-4"

  doctor
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  says simulator 'iOS 17.4 not installed -- run: dot apply'
}

@test "doctor: simulators configured but the Command Line Tools are selected skips the check" {
  fake_xcode 16.0
  stub_tools /Library/Developer/CommandLineTools 16.0
  write_simulators_config "iOS 17.4"

  doctor
  says simulators 'not checked -- Xcode is not the selected developer directory yet'
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

# --- apply.sh: simulator runtimes -----------------------------------------------

@test "apply: no simulators configured never touches xcrun or xcodes" {
  ran="$DOT_TMP/tool_ran"
  for tool in xcrun xcodes; do
    cat >"$STUB/$tool" <<EOF
#!/usr/bin/env bash
echo "$tool \$*" >>"$ran"
exit 0
EOF
    chmod +x "$STUB/$tool"
  done

  apply
  [ "$status" -eq 0 ]
  [ ! -f "$ran" ]
}

@test "apply: a dry run announces a missing simulator and installs nothing" {
  fake_xcode 16.0
  stub_tools "$XCODE/Contents/Developer" 16.0
  write_simulators_config "iOS 17.4"
  stub_xcrun ""
  ran="$DOT_TMP/xcodes_ran"
  cat >"$STUB/xcodes" <<EOF
#!/usr/bin/env bash
echo "xcodes \$*" >>"$ran"
exit 0
EOF
  chmod +x "$STUB/xcodes"
  local before
  before=$(home_snapshot)

  apply 1 "$STUB/code" "$XCODE"
  [ "$status" -eq 0 ]
  [[ $output == *"install iOS 17.4"* ]]
  [ ! -f "$ran" ]
  [ "$(home_snapshot)" = "$before" ]
}

@test "apply: an already-installed simulator is left alone" {
  fake_xcode 16.0
  stub_tools "$XCODE/Contents/Developer" 16.0
  write_simulators_config "iOS 17.4"
  stub_xcrun "iOS 17.4 (17.4) - com.apple.CoreSimulator.SimRuntime.iOS-17-4"
  ran="$DOT_TMP/xcodes_ran"
  cat >"$STUB/xcodes" <<EOF
#!/usr/bin/env bash
echo "xcodes \$*" >>"$ran"
exit 0
EOF
  chmod +x "$STUB/xcodes"

  apply 0 "$STUB/code" "$XCODE"
  [ "$status" -eq 0 ]
  says simulator 'iOS 17.4 already installed'
  [ ! -f "$ran" ]
}

@test "apply: a missing simulator installs via xcodes" {
  fake_xcode 16.0
  stub_tools "$XCODE/Contents/Developer" 16.0
  write_simulators_config "iOS 17.4"
  stub_xcrun ""
  ran="$DOT_TMP/xcodes_ran"
  cat >"$STUB/xcodes" <<EOF
#!/usr/bin/env bash
echo "xcodes \$*" >>"$ran"
exit 0
EOF
  chmod +x "$STUB/xcodes"

  apply 0 "$STUB/code" "$XCODE"
  [ "$status" -eq 0 ]
  says simulator 'iOS 17.4 installed'
  [[ $(cat "$ran") == *"runtimes install iOS 17.4"* ]]
}

@test "apply: a failed simulator install is a warning naming the retry command" {
  fake_xcode 16.0
  stub_tools "$XCODE/Contents/Developer" 16.0
  write_simulators_config "iOS 17.4"
  stub_xcrun ""
  printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB/xcodes"
  chmod +x "$STUB/xcodes"

  apply 0 "$STUB/code" "$XCODE"
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  says simulator 'could not install iOS 17.4 -- retry: xcodes runtimes install "iOS 17.4"'
}

@test "apply: simulators configured but the Command Line Tools are selected skips them" {
  stub_tools /Library/Developer/CommandLineTools 16.0
  write_simulators_config "iOS 17.4"
  ran="$DOT_TMP/xcrun_ran"
  cat >"$STUB/xcrun" <<EOF
#!/usr/bin/env bash
echo "xcrun \$*" >>"$ran"
exit 0
EOF
  chmod +x "$STUB/xcrun"

  apply 0 "$STUB/code" "$XCODE"
  [ "$status" -eq 0 ]
  says simulators 'skipped -- Xcode is not the selected developer directory yet'
  [ ! -f "$ran" ]
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
