#!/usr/bin/env bats
# scripts/lib/xcode.sh — the probes both `chezxcode` and `chezdoctor` read.
#
# These pin the two states that look healthy but aren't, because both are
# reachable straight out of install.sh and neither shows up in `brew bundle
# check`:
#
#   1. The Command Line Tools are the selected toolchain. `xcode-select -p`
#      succeeds, so every naive "is Xcode set up?" check passes — while
#      xcodebuild resolves to the CLT stub with no iOS SDK behind it. install.sh
#      installs the CLT as its very first step, so this is the *default* state
#      of a fresh Mac, not an edge case.
#   2. Xcode is installed and selected but no simulator runtime is downloaded.
#      Since Xcode 16 runtimes ship separately; `simctl list runtimes` then
#      prints its header and nothing else and there is nothing to run an app on.
#
# Everything is driven through stubbed xcode-select/xcodebuild/xcrun so the
# tests describe a machine's state rather than this machine's state.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LIB="$REPO_ROOT/scripts/lib/xcode.sh"
    [ -r "$LIB" ] || skip "scripts/lib/xcode.sh missing"

    STUBS="$BATS_TEST_TMPDIR/bin"
    APPS="$BATS_TEST_TMPDIR/Applications"
    mkdir -p "$STUBS" "$APPS"

    # Each stub reads its answer from the environment, so a test sets the
    # machine's state by exporting variables rather than rewriting stubs.
    cat >"$STUBS/xcode-select" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -p ] || exit 0
[ -n "${STUB_DEVELOPER_DIR:-}" ] || exit 1
echo "$STUB_DEVELOPER_DIR"
EOF
    cat >"$STUBS/xcodebuild" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -version)
        if [ "${STUB_LICENSE_PENDING:-0}" = 1 ]; then
            echo "You have not agreed to the Xcode license agreements." >&2
            exit 69
        fi
        [ "${STUB_XCODEBUILD_OK:-1}" = 1 ] || { echo "xcodebuild: error: broken" >&2; exit 1; }
        echo "Xcode ${STUB_XCODE_VERSION:-26.6}"
        ;;
    -checkFirstLaunchStatus) exit "${STUB_FIRST_LAUNCH_RC:-0}" ;;
    -showsdks) printf '%s\n' "${STUB_SDKS:-}" ;;
    *) exit 0 ;;
esac
EOF
    cat >"$STUBS/xcrun" <<'EOF'
#!/usr/bin/env bash
# Only `xcrun simctl list runtimes` is probed; mimic its real shape, which is a
# bare "== Runtimes ==" header when nothing is downloaded.
if [ "$1" = simctl ]; then
    echo "== Runtimes =="
    printf '%s' "${STUB_RUNTIMES:-}" | sed '/^$/d'
fi
EOF
    chmod +x "$STUBS"/*
    PATH="$STUBS:$PATH"
    export PATH XCODE_APPS_DIR="$APPS"

    # shellcheck source=../scripts/lib/xcode.sh
    . "$LIB"
}

# The lib is idempotent-guarded, so a second source in the same shell is a no-op;
# bats gives each test a fresh shell, so this only matters if that ever changes.
@test "sourcing twice is a no-op" {
    . "$LIB"
    run xcode_selected_is_full
    [ "$status" -eq 1 ]
}

# ─── The Command Line Tools trap ───────────────────────────────────────────────

@test "CLT selected: xcode-select -p succeeds but is not a full Xcode" {
    export STUB_DEVELOPER_DIR="/Library/Developer/CommandLineTools"
    # The naive check every other tool makes — this is why it isn't enough.
    run xcode-select -p
    [ "$status" -eq 0 ]

    run xcode_selected_is_full
    [ "$status" -eq 1 ]
}

@test "CLT selected with no Xcode.app: xcode_app_path finds nothing" {
    export STUB_DEVELOPER_DIR="/Library/Developer/CommandLineTools"
    run xcode_app_path
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "CLT selected but Xcode.app present: falls back to the app in /Applications" {
    export STUB_DEVELOPER_DIR="/Library/Developer/CommandLineTools"
    mkdir -p "$APPS/Xcode.app"
    run xcode_app_path
    [ "$status" -eq 0 ]
    [ "$output" = "$APPS/Xcode.app" ]

    # Finding the app must NOT imply it's the active toolchain — conflating the
    # two is exactly how a machine ends up unable to build for iOS.
    run xcode_selected_is_full
    [ "$status" -eq 1 ]
}

@test "Xcode selected: reported as full, and the app path comes from the selection" {
    export STUB_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    run xcode_selected_is_full
    [ "$status" -eq 0 ]
    run xcode_app_path
    [ "$status" -eq 0 ]
    [ "$output" = "/Applications/Xcode.app" ]
}

# A deliberately-chosen versioned Xcode must win over anything in /Applications.
@test "a versioned Xcode selection is preferred over the /Applications glob" {
    export STUB_DEVELOPER_DIR="/Applications/Xcode-26.6.app/Contents/Developer"
    mkdir -p "$APPS/Xcode.app"
    run xcode_app_path
    [ "$output" = "/Applications/Xcode-26.6.app" ]
}

# ─── Licence and first launch ──────────────────────────────────────────────────

@test "licence pending: xcodebuild fails and the reason is identified" {
    export STUB_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" STUB_LICENSE_PENDING=1
    # Non-zero, not 1: the real xcodebuild exits 69 (EX_UNAVAILABLE) on the
    # licence gate, so callers must never test for a specific failure code.
    run xcode_build_works
    [ "$status" -ne 0 ]
    run xcode_license_pending
    [ "$status" -eq 0 ]
}

# A broken xcodebuild must not be misreported as a licence problem — they have
# different fixes, and doctor prints whichever this says.
@test "xcodebuild broken for another reason is not reported as a licence issue" {
    export STUB_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" STUB_XCODEBUILD_OK=0
    run xcode_build_works
    [ "$status" -eq 1 ]
    run xcode_license_pending
    [ "$status" -eq 1 ]
}

@test "first-launch status is taken from xcodebuild's own exit code" {
    export STUB_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    STUB_FIRST_LAUNCH_RC=0 run xcode_first_launch_done
    [ "$status" -eq 0 ]
    STUB_FIRST_LAUNCH_RC=1 run xcode_first_launch_done
    [ "$status" -eq 1 ]
}

# ─── iOS SDK ───────────────────────────────────────────────────────────────────

@test "no iOS Simulator SDK when only macOS SDKs are listed" {
    export STUB_SDKS="macOS SDKs:
	macOS 26.5                    	-sdk macosx26.5"
    run xcode_has_ios_sdk
    [ "$status" -eq 1 ]
}

@test "iOS Simulator SDK detected when listed" {
    export STUB_SDKS="iOS Simulator SDKs:
	Simulator - iOS 26.5          	-sdk iphonesimulator26.5"
    run xcode_has_ios_sdk
    [ "$status" -eq 0 ]
}

# ─── The missing-runtime trap ──────────────────────────────────────────────────

@test "no runtimes downloaded: simctl prints only its header" {
    export STUB_RUNTIMES=""
    run xcode_ios_runtimes
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run xcode_has_ios_runtime
    [ "$status" -eq 1 ]
}

# Registered-but-not-downloaded runtimes still appear in the listing, tagged
# unavailable. Counting them would report a machine as ready when nothing boots.
@test "runtimes tagged unavailable do not count as installed" {
    export STUB_RUNTIMES="iOS 26.5 (26.5 - 23F79) - com.apple.CoreSimulator.SimRuntime.iOS-26-5 (unavailable, runtime profile not found)"
    run xcode_ios_runtimes
    [ -z "$output" ]
    run xcode_has_ios_runtime
    [ "$status" -eq 1 ]
}

@test "an available runtime is detected and summarised" {
    export STUB_RUNTIMES="iOS 26.5 (26.5 - 23F79) - com.apple.CoreSimulator.SimRuntime.iOS-26-5"
    run xcode_has_ios_runtime
    [ "$status" -eq 0 ]
    run xcode_ios_runtimes_summary
    [ "$output" = "iOS 26.5" ]
}

# Joining with `paste -sd', '` would interleave the two delimiter characters and
# produce "iOS 26.5,iOS 18.6" — BSD paste cycles a multi-char -d.
@test "multiple runtimes are summarised comma-separated on one line" {
    export STUB_RUNTIMES="iOS 26.5 (26.5 - 23F79) - com.apple.CoreSimulator.SimRuntime.iOS-26-5
iOS 18.6 (18.6 - 22G86) - com.apple.CoreSimulator.SimRuntime.iOS-18-6"
    run xcode_ios_runtimes_summary
    [ "$output" = "iOS 26.5, iOS 18.6" ]
}

# tvOS/watchOS runtimes are real but irrelevant: an iOS app can't run on them.
@test "a tvOS-only runtime does not satisfy the iOS check" {
    export STUB_RUNTIMES="tvOS 26.5 (26.5 - 23F79) - com.apple.CoreSimulator.SimRuntime.tvOS-26-5"
    run xcode_has_ios_runtime
    [ "$status" -eq 1 ]
}

# ─── xcode_ready — the whole verdict ───────────────────────────────────────────

@test "xcode_ready is true only when all five pieces hold" {
    export STUB_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    export STUB_SDKS="	Simulator - iOS 26.5          	-sdk iphonesimulator26.5"
    export STUB_RUNTIMES="iOS 26.5 (26.5 - 23F79) - com.apple.CoreSimulator.SimRuntime.iOS-26-5"
    run xcode_ready
    [ "$status" -eq 0 ]
}

# The exact shape of a fresh install.sh run: Homebrew's Swift tooling is all
# there, but the CLT are still selected.
@test "xcode_ready is false when the CLT are still selected" {
    export STUB_DEVELOPER_DIR="/Library/Developer/CommandLineTools"
    export STUB_SDKS="	Simulator - iOS 26.5          	-sdk iphonesimulator26.5"
    export STUB_RUNTIMES="iOS 26.5 (26.5 - 23F79) - com.apple.CoreSimulator.SimRuntime.iOS-26-5"
    run xcode_ready
    [ "$status" -eq 1 ]
}

# Xcode fully installed, licensed and selected — and still nothing to run on.
@test "xcode_ready is false when only the simulator runtime is missing" {
    export STUB_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    export STUB_SDKS="	Simulator - iOS 26.5          	-sdk iphonesimulator26.5"
    export STUB_RUNTIMES=""
    run xcode_ready
    [ "$status" -eq 1 ]
}

# ─── pipefail safety ───────────────────────────────────────────────────────────
# Both callers run under `set -o pipefail`. A probe written as
# `xcodebuild … | grep -q` then yields *xcodebuild's* exit code, not grep's —
# and xcodebuild exits 69 in exactly the licence-pending case, so the piped form
# reports "no licence problem" precisely when there is one. Same trap for
# -showsdks whenever xcodebuild is unhappy for any reason.

@test "xcode_license_pending survives set -o pipefail" {
    export STUB_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" STUB_LICENSE_PENDING=1
    set -o pipefail
    run xcode_license_pending
    [ "$status" -eq 0 ]
}

@test "xcode_has_ios_sdk survives set -o pipefail" {
    export STUB_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    export STUB_SDKS="	Simulator - iOS 26.5          	-sdk iphonesimulator26.5"
    set -o pipefail
    run xcode_has_ios_sdk
    [ "$status" -eq 0 ]
}

@test "xcode_ios_runtimes survives set -o pipefail with nothing installed" {
    export STUB_RUNTIMES=""
    set -o pipefail
    run xcode_has_ios_runtime
    [ "$status" -eq 1 ]
    run xcode_ios_runtimes
    [ "$status" -eq 0 ]
}
