#!/usr/bin/env bats
# The Xcode section of `chez doctor` — the one that catches a machine which
# passed every other check and still cannot build an iOS app.
#
# It is module-gated and branchy, so each arm is pinned separately, especially
# "no Xcode" collapsing to ONE failure rather than six: six red lines for one
# root cause is what makes a health report unreadable.

setup() {
    load '../../../core/testing/helper'
    load '../../../core/testing/doctor'
    doctor_iso_setup
}

# stub_xcode_machine MODULES DEVDIR [licensed] [firstlaunch] [runtime]
stub_xcode_machine() {
    local modules="$1" devdir="$2" licensed="${3:-1}" firstlaunch="${4:-1}" runtime="${5:-1}"
    XAPPS="$ISO_HOME/Applications"
    mkdir -p "$XAPPS"

    cat >"$STUB_BIN/chezmoi" <<EOF
#!/usr/bin/env bash
case "\$1" in
    --version) echo "chezmoi version v2.72.0, commit none, built none" ;;
    data) echo '{"modules":$modules}' ;;
    doctor | status) exit 0 ;;
    *) exit 0 ;;
esac
EOF
    cat >"$STUB_BIN/xcode-select" <<EOF
#!/usr/bin/env bash
[ "\$1" = -p ] && echo "$devdir"
exit 0
EOF
    cat >"$STUB_BIN/xcodebuild" <<EOF
#!/usr/bin/env bash
case "\$1" in
    -version)
        [ "$licensed" = 1 ] || {
            echo "You have not agreed to the Xcode license agreements." >&2; exit 69; }
        case "$devdir" in */Xcode*.app/Contents/Developer) echo "Xcode 26.6" ;; *) exit 1 ;; esac ;;
    -checkFirstLaunchStatus) [ "$firstlaunch" = 1 ] || exit 1 ;;
    -showsdks)
        case "$devdir" in
            */Xcode*.app/Contents/Developer) echo "  Simulator - iOS 26.5  -sdk iphonesimulator26.5" ;;
            *) echo "  macOS 26.5  -sdk macosx26.5" ;;
        esac ;;
esac
exit 0
EOF
    cat >"$STUB_BIN/xcrun" <<EOF
#!/usr/bin/env bash
echo "== Runtimes =="
[ "$runtime" = 1 ] &&
    echo "iOS 26.5 (26.5 - 23F79) - com.apple.CoreSimulator.SimRuntime.iOS-26-5"
exit 0
EOF
    chmod +x "$STUB_BIN"/chezmoi "$STUB_BIN"/xcode-select "$STUB_BIN"/xcodebuild "$STUB_BIN"/xcrun
    doctor_git_init
}

# The module gate goes through jq, which the isolated PATH deliberately lacks;
# doctor_path_with puts just that one directory back.
run_doctor_xcode() {
    local p
    p="$(doctor_path_with jq)" || skip "jq not installed"
    doctor_run_with "$p" XCODE_APPS_DIR="$XAPPS"
}

@test "no Xcode collapses to a single failure, not six" {
    stub_xcode_machine '["appleDev"]' "/Library/Developer/CommandLineTools" 0 0 0
    run_doctor_xcode
    [[ "$output" == *"Xcode / iOS (appleDev)"* ]] || return 1
    [[ "$output" == *"no Xcode.app — install.sh only installs the Command Line Tools"* ]] || return 1
    # The five downstream checks must stay quiet; they all fail for this one reason.
    [[ "$output" != *"no iOS Simulator SDK"* ]] || return 1
    [[ "$output" != *"first-launch components pending"* ]] || return 1
}

@test "a fully ready machine passes every Xcode check" {
    mkdir -p "$ISO_HOME/Applications"
    stub_xcode_machine '["appleDev"]' "/Applications/Xcode.app/Contents/Developer"
    run_doctor_xcode
    [[ "$output" == *"Xcode installed: /Applications/Xcode.app"* ]] || return 1
    [[ "$output" == *"xcodebuild runs: Xcode 26.6"* ]] || return 1
    [[ "$output" == *"first-launch components installed"* ]] || return 1
    [[ "$output" == *"iOS Simulator SDK present"* ]] || return 1
    [[ "$output" == *"iOS simulator runtime: iOS 26.5"* ]] || return 1
}

# The trap this whole feature exists for: Xcode is installed, but the Command
# Line Tools still own xcode-select, so nothing can build for iOS.
@test "Xcode installed but CLT selected is reported as such" {
    mkdir -p "$ISO_HOME/Applications/Xcode.app"
    stub_xcode_machine '["appleDev"]' "/Library/Developer/CommandLineTools"
    run_doctor_xcode
    [[ "$output" == *"Xcode installed:"* ]] || return 1
    [[ "$output" == *"xcode-select points at /Library/Developer/CommandLineTools, not Xcode.app"* ]] || return 1
}

# A pending licence and a broken xcodebuild have different fixes; doctor must
# name the right one.
@test "a pending licence is named, not reported as a generic failure" {
    mkdir -p "$ISO_HOME/Applications"
    stub_xcode_machine '["appleDev"]' "/Applications/Xcode.app/Contents/Developer" 0
    run_doctor_xcode
    [[ "$output" == *"Xcode licence not accepted"* ]] || return 1
    [[ "$output" != *"xcodebuild fails — run"* ]] || return 1
}

# The state this Mac was actually in: everything green except the runtime.
@test "a missing simulator runtime is the only failure" {
    mkdir -p "$ISO_HOME/Applications"
    stub_xcode_machine '["appleDev"]' "/Applications/Xcode.app/Contents/Developer" 1 1 0
    run_doctor_xcode
    [[ "$output" == *"no iOS simulator runtime — nothing to run an app on"* ]] || return 1
    [[ "$output" == *"iOS Simulator SDK present"* ]] || return 1
}

@test "the Xcode section is absent without the appleDev module" {
    stub_xcode_machine '["macApps"]' "/Library/Developer/CommandLineTools" 0 0 0
    run_doctor_xcode
    [[ "$output" != *"Xcode / iOS"* ]] || return 1
    [[ "$output" != *"chez xcode"* ]] || return 1
}

# ─── Brewfile resolution ────────────────────────────────────────────────────
# The resolver itself lives in features/brew/lib/tiers.sh and is exercised in
# features/brew/tests/tiers.bats. What matters here is that doctor.sh keeps
# using it for BOTH directions — "is my active set installed?" and "what's
# installed that no active tier declares?". They used to disagree: the first
# asked the resolver, the second globbed every `Brewfile.*` on disk, so a tier
# this machine does not enable still vouched for whatever it declared.
