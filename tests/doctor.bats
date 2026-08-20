#!/usr/bin/env bats
# Coverage for doctor.sh's deterministic, offline-stubbable sections: XDG
# layout, source-repo presence, and the chezmoi-version floor check. Sections
# needing real gh/az/gcloud/brew/code/mise/op state aren't covered here —
# doctor.sh has no seam to inject fake credentials for those, and this repo's
# CI runner doesn't have them installed anyway.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    DOCTOR="$REPO_ROOT/scripts/bin/doctor.sh"
    command -v git >/dev/null 2>&1 || skip "git not installed"

    ISO_HOME="$(mktemp -d)"
    ISO_REPO="$(mktemp -d)"
    STUB_BIN="$(mktemp -d)"
    # A minimal, deterministic PATH: real coreutils/git only, no
    # Homebrew-installed brew/code/mise/gh/az/gcloud/op — so those sections
    # short-circuit to "not installed" instead of exercising real machine
    # state (which would make this test's output nondeterministic and slow).
    ISO_PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
}

teardown() {
    rm -rf "${ISO_HOME:-}" "${ISO_REPO:-}" "${STUB_BIN:-}"
}

run_doctor() {
    run env HOME="$ISO_HOME" DOTFILES_DIR="$ISO_REPO" PATH="$ISO_PATH" bash "$DOCTOR"
}

# ─── XDG layout ─────────────────────────────────────────────────────────────

@test "doctor.sh fails when a legacy .zshrc is present" {
    touch "$ISO_HOME/.zshrc"
    run_doctor
    [[ "$output" == *"legacy $ISO_HOME/.zshrc present"* ]]
}

@test "doctor.sh passes XDG layout when only the managed files exist" {
    mkdir -p "$ISO_HOME/.config/zsh"
    touch "$ISO_HOME/.config/zsh/.zshrc" "$ISO_HOME/.zshenv"
    run_doctor
    [[ "$output" == *"~/.config/zsh/.zshrc present"* ]]
    [[ "$output" == *"~/.zshenv present"* ]]
    [[ "$output" == *"no legacy .zshrc"* ]]
    [[ "$output" != *"legacy $ISO_HOME"* ]]
}

@test "doctor.sh fails when ~/.config/zsh/.zshrc is missing" {
    run_doctor
    [[ "$output" == *"~/.config/zsh/.zshrc missing"* ]]
}

# ─── Source repo ────────────────────────────────────────────────────────────

@test "doctor.sh fails when DOTFILES_DIR has no .git" {
    run_doctor
    [[ "$output" == *"repo missing at $ISO_REPO"* ]]
}

@test "doctor.sh passes repo presence and clean-tree checks for a real git repo" {
    (cd "$ISO_REPO" && git init -q -b main)
    run_doctor
    [[ "$output" == *"repo at $ISO_REPO"* ]]
    [[ "$output" == *"repo working tree clean"* ]]
}

# ─── chezmoi version comparison ─────────────────────────────────────────────

stub_chezmoi() {
    local version="$1"
    cat >"$STUB_BIN/chezmoi" <<EOF
#!/usr/bin/env bash
case "\$1" in
    --version) echo "chezmoi version $version, commit none, built none" ;;
    doctor) exit 0 ;;
    status) exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$STUB_BIN/chezmoi"
}

@test "doctor.sh fails when the installed chezmoi is older than the repo floor" {
    (cd "$ISO_REPO" && git init -q -b main)
    mkdir -p "$ISO_REPO/src"
    echo "2.50.0" >"$ISO_REPO/src/.chezmoiversion"
    stub_chezmoi "v2.40.0"
    run_doctor
    [[ "$output" == *"chezmoi 2.40.0 is older than the repo minimum 2.50.0"* ]]
}

@test "doctor.sh passes when the installed chezmoi meets the repo floor" {
    (cd "$ISO_REPO" && git init -q -b main)
    mkdir -p "$ISO_REPO/src"
    echo "2.50.0" >"$ISO_REPO/src/.chezmoiversion"
    stub_chezmoi "v2.72.0"
    run_doctor
    [[ "$output" == *"chezmoi 2.72.0 meets repo minimum 2.50.0"* ]]
}

# ─── Xcode / iOS (appleDev) ─────────────────────────────────────────────────
# The section that catches a machine which passed every other check and still
# cannot build an iOS app. It is module-gated and branchy, so each arm is pinned
# separately — especially "no Xcode" collapsing to ONE failure rather than six,
# since six red lines for one root cause is what makes a health check unreadable.

# cm_has_module goes through jq; the isolated PATH deliberately has no Homebrew,
# so put jq's real directory back for these tests only.
_xcode_path() {
    local jq_bin
    jq_bin="$(command -v jq 2>/dev/null)" || return 1
    printf '%s:%s' "$STUB_BIN" "$(dirname "$jq_bin"):/usr/bin:/bin:/usr/sbin:/sbin"
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
    data) echo '{"modules":$modules,"profile":"personal"}' ;;
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
    (cd "$ISO_REPO" && git init -q -b main)
}

run_doctor_xcode() {
    local p
    p="$(_xcode_path)" || skip "jq not installed"
    run env HOME="$ISO_HOME" DOTFILES_DIR="$ISO_REPO" PATH="$p" \
        XCODE_APPS_DIR="$XAPPS" bash "$DOCTOR"
}

@test "doctor: no Xcode collapses to a single failure, not six" {
    stub_xcode_machine '["appleDev"]' "/Library/Developer/CommandLineTools" 0 0 0
    run_doctor_xcode
    [[ "$output" == *"Xcode / iOS (appleDev)"* ]]
    [[ "$output" == *"no Xcode.app — install.sh only installs the Command Line Tools"* ]]
    # The five downstream checks must stay quiet; they all fail for this one reason.
    [[ "$output" != *"no iOS Simulator SDK"* ]]
    [[ "$output" != *"first-launch components pending"* ]]
}

@test "doctor: a fully ready machine passes every Xcode check" {
    mkdir -p "$ISO_HOME/Applications"
    stub_xcode_machine '["appleDev"]' "/Applications/Xcode.app/Contents/Developer"
    run_doctor_xcode
    [[ "$output" == *"Xcode installed: /Applications/Xcode.app"* ]]
    [[ "$output" == *"xcodebuild runs: Xcode 26.6"* ]]
    [[ "$output" == *"first-launch components installed"* ]]
    [[ "$output" == *"iOS Simulator SDK present"* ]]
    [[ "$output" == *"iOS simulator runtime: iOS 26.5"* ]]
}

# The trap this whole feature exists for: Xcode is installed, but the Command
# Line Tools still own xcode-select, so nothing can build for iOS.
@test "doctor: Xcode installed but CLT selected is reported as such" {
    mkdir -p "$ISO_HOME/Applications/Xcode.app"
    stub_xcode_machine '["appleDev"]' "/Library/Developer/CommandLineTools"
    run_doctor_xcode
    [[ "$output" == *"Xcode installed:"* ]]
    [[ "$output" == *"xcode-select points at /Library/Developer/CommandLineTools, not Xcode.app"* ]]
}

# A pending licence and a broken xcodebuild have different fixes; doctor must
# name the right one.
@test "doctor: a pending licence is named, not reported as a generic failure" {
    mkdir -p "$ISO_HOME/Applications"
    stub_xcode_machine '["appleDev"]' "/Applications/Xcode.app/Contents/Developer" 0
    run_doctor_xcode
    [[ "$output" == *"Xcode licence not accepted"* ]]
    [[ "$output" != *"xcodebuild fails — run"* ]]
}

# The state this Mac was actually in: everything green except the runtime.
@test "doctor: a missing simulator runtime is the only failure" {
    mkdir -p "$ISO_HOME/Applications"
    stub_xcode_machine '["appleDev"]' "/Applications/Xcode.app/Contents/Developer" 1 1 0
    run_doctor_xcode
    [[ "$output" == *"no iOS simulator runtime — nothing to run an app on"* ]]
    [[ "$output" == *"iOS Simulator SDK present"* ]]
}

@test "doctor: the Xcode section is absent without the appleDev module" {
    stub_xcode_machine '["macApps"]' "/Library/Developer/CommandLineTools" 0 0 0
    run_doctor_xcode
    [[ "$output" != *"Xcode / iOS"* ]]
    [[ "$output" != *"chezxcode"* ]]
}
