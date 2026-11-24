#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox
  BIN="$DOT_TMP/bin"
  CORESIM="$DOT_TMP/CoreSimulator"
  XCODE="$DOT_TMP/Xcode.app/Contents/Developer"
  CALLS="$DOT_TMP/calls"
  mkdir -p "$BIN" "$CORESIM" "$XCODE/usr/bin"
  : >"$CALLS"
  CLAUDE="$BIN/claude"
  CODE="$BIN/code"
  recorder code >"$BIN/code"
  recorder claude >"$CLAUDE"
  recorder xcodebuild >"$XCODE/usr/bin/xcodebuild"
  chmod +x "$BIN/code" "$CLAUDE" "$XCODE/usr/bin/xcodebuild"
  selected "$XCODE"
}
teardown() { teardown_sandbox; }

recorder() {
  printf '#!/usr/bin/env bash\necho "%s $*" >>"%s"\n' "$1" "$CALLS"
}

selected() {
  printf '#!/usr/bin/env bash\necho %q\n' "$1" >"$DOT_TMP/xcode-select"
  chmod +x "$DOT_TMP/xcode-select"
}

hook() {
  local name=$1 dry=${2:-0}
  run env PATH="$BIN:$PATH" DOT_ROOT="$DOT_ROOT" HOME="$HOME" \
    DOT_CONFIG="$DOT_CONFIG" DOT_STATE="$DOT_STATE" DOT_DRY_RUN="$dry" \
    DOT_CORESIM_ROOT="$CORESIM" DOT_XCODE_SELECT="$DOT_TMP/xcode-select" DOT_CLAUDE_BIN="$CLAUDE" DOT_CODE_BIN="$CODE" DOT_COLUMNS=400 \
    DOT_MODULE=ios DOT_MODULE_DIR="$DOT_ROOT/modules/ios" \
    "$BASH" "$DOT_ROOT/modules/ios/$name.sh"
}

with_extensions() {
  mkdir -p "$HOME/.vscode/extensions"
  local id json='[]'
  for id in "$@"; do
    json=$(jq --arg id "$id" '. + [{identifier: {id: $id}}]' <<<"$json")
  done
  printf '%s\n' "$json" >"$HOME/.vscode/extensions/extensions.json"
}

with_plugins() {
  mkdir -p "$HOME/.claude/plugins"
  local id json='{"version": 2, "plugins": {}}'
  for id in "$@"; do
    json=$(jq --arg id "$id" '.plugins[$id] = [{scope: "user", version: "1.0.0"}]' <<<"$json")
  done
  printf '%s\n' "$json" >"$HOME/.claude/plugins/installed_plugins.json"
}

with_runtime() {
  mkdir -p "$CORESIM/Volumes/${1}_23B80/Library/Developer/CoreSimulator/Profiles/Runtimes/$1 26.1.simruntime"
}

linked_swift_format() {
  ln -s "$DOT_ROOT/modules/ios/home/.swift-format" "$HOME/.swift-format"
}

in_registry() {
  mkdir -p "$CORESIM/Images"
  printf 'bplist00\0' >"$CORESIM/Images/images.plist"
  printf 'com.apple.CoreSimulator.SimRuntime.%s\0' "$@" >>"$CORESIM/Images/images.plist"
}

@test "apply: installs only the extensions VS Code does not have" {
  with_extensions swiftlang.swift-vscode
  with_runtime iOS
  with_runtime watchOS

  hook apply
  [ "$status" -eq 0 ]
  grep -qx 'code --install-extension sweetpad.sweetpad' "$CALLS"
  ! grep -q 'swiftlang.swift-vscode' "$CALLS"
}

@test "apply: an installed extension is one line, without the code CLI's chatter" {
  with_extensions swiftlang.swift-vscode
  with_runtime iOS
  with_runtime watchOS
  cat >"$BIN/code" <<'EOF'
#!/usr/bin/env bash
echo 'Installing extensions...'
echo '(node:6554) [DEP0169] DeprecationWarning: `url.parse()` behavior is not standardized' >&2
echo '(Use `Code --trace-deprecation ...` to show where the warning was created)' >&2
echo "Installing extension '$2'..."
echo "Extension '$2' v0.2.21 was successfully installed."
EOF

  hook apply
  [ "$status" -eq 0 ]
  [[ $output =~ installed\ +extension\ sweetpad\.sweetpad ]]
  [[ $output != *Installing* ]]
  [[ $output != *node:* ]]
  [[ $output != *trace-deprecation* ]]
  [[ $output != *successfully* ]]
}

@test "apply: a failed extension install keeps what code said, and is a failure" {
  with_extensions swiftlang.swift-vscode
  with_runtime iOS
  with_runtime watchOS
  printf '#!/usr/bin/env bash\necho "Installing extensions..."\necho "Extension %s not found."\nexit 1\n' "'sweetpad.sweetpad'" >"$BIN/code"

  hook apply
  [ "$status" -ne 0 ]
  [[ $output == *"Extension 'sweetpad.sweetpad' not found."* ]]
  says extension 'sweetpad.sweetpad did not install'
  [[ ! $output =~ installed\ +extension ]]
}

@test "apply: an extension id is matched without regard to case" {
  with_extensions SweetPad.SweetPad SwiftLang.Swift-VSCode
  with_plugins swift-lsp@claude-plugins-official
  with_runtime iOS
  with_runtime watchOS

  hook apply
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  says extensions '2 VS Code extensions installed'
}

@test "apply: installs the Claude Code plugin at user scope, only when it is missing" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_runtime iOS
  with_runtime watchOS

  hook apply
  [ "$status" -eq 0 ]
  grep -qx 'claude plugin install swift-lsp@claude-plugins-official --scope user' "$CALLS"
  [[ $output =~ installed\ +plugin\ swift-lsp@claude-plugins-official ]]

  : >"$CALLS"
  with_plugins swift-lsp@claude-plugins-official
  hook apply
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  says plugins '1 Claude Code plugin installed'
}

@test "apply: a plugin installed only for one project is installed for the user" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_runtime iOS
  with_runtime watchOS
  mkdir -p "$HOME/.claude/plugins"
  printf '{"version":2,"plugins":{"swift-lsp@claude-plugins-official":[{"scope":"project"}]}}\n' \
    >"$HOME/.claude/plugins/installed_plugins.json"

  hook apply
  grep -qx 'claude plugin install swift-lsp@claude-plugins-official --scope user' "$CALLS"
}

@test "apply: a failed plugin install keeps what claude said, and is a failure" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_runtime iOS
  with_runtime watchOS
  printf '#!/usr/bin/env bash\necho "Failed to install plugin: marketplace not found"\nexit 1\n' >"$CLAUDE"

  hook apply
  [ "$status" -ne 0 ]
  [[ $output == *'marketplace not found'* ]]
  says plugin 'swift-lsp@claude-plugins-official did not install'
}

@test "apply: without the claude CLI the plugin waits, and nothing fails" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_runtime iOS
  with_runtime watchOS
  CLAUDE="$DOT_TMP/no-claude"

  hook apply
  [ "$status" -eq 0 ]
  [[ $output == *'waits for the claude CLI'* ]]
  [ ! -s "$CALLS" ]
}

@test "apply: downloads only the simulator runtime that is missing" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_runtime iOS

  hook apply
  [ "$status" -eq 0 ]
  grep -qx 'xcodebuild -downloadPlatform watchOS' "$CALLS"
  ! grep -q 'downloadPlatform iOS' "$CALLS"
}

@test "apply: without the code CLI, a dry run and a real run announce the same extensions" {
  with_plugins swift-lsp@claude-plugins-official
  with_runtime iOS
  with_runtime watchOS
  CODE="$DOT_TMP/no-code"
  local dry

  hook apply 1
  [ "$status" -eq 0 ]
  dry=$(grep -E 'extension +(sweetpad|swiftlang)' <<<"$output" | grep -v 'waits for')

  hook apply
  [ "$status" -ne 0 ]
  [ -n "$dry" ]
  [ "$dry" = "$(grep -E 'extension +(sweetpad|swiftlang)' <<<"$output" | grep -v 'waits for')" ]
  says extension 'sweetpad.sweetpad waits for the code CLI'
}

@test "apply: a runtime under Profiles/Runtimes counts as present" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_plugins swift-lsp@claude-plugins-official
  mkdir -p "$CORESIM/Profiles/Runtimes/iOS 18.0.simruntime" "$CORESIM/Profiles/Runtimes/watchOS 11.0.simruntime"

  hook apply
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "apply: a runtime listed only in the Images registry counts as present" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_plugins swift-lsp@claude-plugins-official
  in_registry iOS-27-2 watchOS-27-2

  hook apply
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "apply: a watchOS entry in the Images registry is not taken for iOS" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_plugins swift-lsp@claude-plugins-official
  in_registry watchOS-27-2

  hook apply
  [ "$status" -eq 0 ]
  grep -qx 'xcodebuild -downloadPlatform iOS' "$CALLS"
  ! grep -q 'downloadPlatform watchOS' "$CALLS"
}

@test "apply: a failed runtime download is a failure, not a pass" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_runtime iOS
  printf '#!/usr/bin/env bash\necho "no network"\nexit 70\n' >"$XCODE/usr/bin/xcodebuild"

  hook apply
  [ "$status" -ne 0 ]
  says runtime 'watchOS did not download'
}

@test "apply: without Xcode selected it warns, and downloads nothing" {
  selected /Library/Developer/CommandLineTools
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_plugins swift-lsp@claude-plugins-official

  hook apply
  [ "$status" -eq "$DOT_STATUS_WARN" ]
  [[ $output == *'xcodes install'* ]]
  [ ! -s "$CALLS" ]
}

@test "apply: a dry run names every install and runs none of them" {
  local before after
  before=$(home_snapshot)

  hook apply 1
  [ "$status" -eq 0 ]
  says extension sweetpad.sweetpad
  says plugin swift-lsp@claude-plugins-official
  says runtime 'iOS simulator'
  says runtime 'watchOS simulator'
  [ ! -s "$CALLS" ]

  after=$(home_snapshot)
  [ "$before" = "$after" ]
}

@test "doctor: green once Xcode, both runtimes, both extensions and the plugin are there" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_plugins swift-lsp@claude-plugins-official
  with_runtime iOS
  with_runtime watchOS

  hook doctor
  [ "$status" -eq 0 ]
  says Xcode 'Xcode.app selected'
  says plugins 'swift-lsp installed in Claude Code'
}

@test "doctor: a missing watchOS runtime fails and is named" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_runtime iOS

  hook doctor
  [ "$status" -ne 0 ]
  says runtimes 'no watchOS simulator'
}

@test "doctor: runtimes known only to the Images registry are present" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_plugins swift-lsp@claude-plugins-official
  in_registry iOS-27-2-iPhone19-4 watchOS-27-2

  hook doctor
  [ "$status" -eq 0 ]
  says runtimes 'iOS and watchOS simulators present'
}

@test "doctor: the Command Line Tools alone are a failure, and runtimes are not called green" {
  selected /Library/Developer/CommandLineTools
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_runtime iOS
  with_runtime watchOS

  hook doctor
  [ "$status" -ne 0 ]
  says Xcode 'no working Xcode is selected (xcode-select -p: /Library/Developer/CommandLineTools)'
  ! says runtimes 'iOS and watchOS simulators present'
}

@test "doctor: a selected Xcode that was since deleted is not called working" {
  selected /Applications/Gone.app/Contents/Developer
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode

  hook doctor
  [ "$status" -ne 0 ]
  says Xcode 'no working Xcode is selected'
}

@test "doctor: a missing extension fails" {
  with_extensions swiftlang.swift-vscode
  with_runtime iOS
  with_runtime watchOS

  hook doctor
  [ "$status" -ne 0 ]
  says extensions 'not in VS Code: sweetpad.sweetpad'
}

@test "doctor: a missing plugin fails when claude is there to install it" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_runtime iOS
  with_runtime watchOS

  hook doctor
  [ "$status" -ne 0 ]
  says plugins 'not in Claude Code: swift-lsp@claude-plugins-official'
}

@test "doctor: without the claude CLI the plugin is not checked, and not called green" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_runtime iOS
  with_runtime watchOS
  CLAUDE="$DOT_TMP/no-claude"

  hook doctor
  [ "$status" -eq 0 ]
  [[ $output == *'checked once the claude CLI is installed'* ]]
  ! says plugins 'swift-lsp installed in Claude Code'
}

@test "doctor: never invokes code, claude or xcodebuild" {
  hook doctor
  [ ! -s "$CALLS" ]
}

@test "remove: silent on a machine that never had any of it" {
  selected /Library/Developer/CommandLineTools

  hook remove
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remove: silent on a Mac with Xcode and all of it that never enabled ios" {
  with_extensions sweetpad.sweetpad swiftlang.swift-vscode
  with_plugins swift-lsp@claude-plugins-official
  with_runtime iOS
  with_runtime watchOS

  hook remove
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remove: names what is left, and deletes none of it" {
  linked_swift_format
  with_extensions sweetpad.sweetpad
  with_plugins swift-lsp@claude-plugins-official
  with_runtime iOS
  local before after
  before=$(home_snapshot)

  hook remove
  says 'left alone' 'VS Code extensions: sweetpad.sweetpad'
  says 'left alone' 'Claude Code plugins: swift-lsp@claude-plugins-official'
  [[ $output == *'claude plugin uninstall swift-lsp@claude-plugins-official'* ]]
  says 'left alone' 'iOS simulator runtimes'
  [[ $output == *"$DOT_TMP/Xcode.app -- over 10 GB"* ]]
  [ ! -s "$CALLS" ]
  [ -d "$CORESIM/Volumes/iOS_23B80" ]

  after=$(home_snapshot)
  [ "$before" = "$after" ]
}
