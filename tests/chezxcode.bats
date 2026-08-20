#!/usr/bin/env bats
# scripts/bin/xcode.sh (`chezxcode`) — the consent gates around a ~40 GB download.
#
# The safety property under test is one sentence: **`xcodes install` never runs
# without a person saying yes.** Two bugs violated it during development, both
# invisible on a developer's own terminal and both live only in the headless
# case — a hook, a CI job, a script:
#
#   1. The terminal check was `[ -r /dev/tty ]`, which passes in contexts where
#      the device still cannot be opened. The prompt's output vanished into a
#      "Device not configured" error and the run proceeded to download.
#   2. `read || reply=""` fell through to the `[Y/n]` default, so EOF — stdin
#      closed, terminal gone — was indistinguishable from pressing Enter and
#      counted as consent.
#
# Every test therefore asserts on a marker file the stubbed `xcodes` writes when
# invoked, rather than on wording: the wording may change, the invariant may not.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/scripts/bin/xcode.sh"
    [ -r "$SCRIPT" ] || skip "scripts/bin/xcode.sh missing"

    STUBS="$BATS_TEST_TMPDIR/bin"
    APPS="$BATS_TEST_TMPDIR/Applications"
    MARKER="$BATS_TEST_TMPDIR/xcodes-was-invoked"
    mkdir -p "$STUBS" "$APPS"

    # A fresh Mac straight out of install.sh: CLT selected, no Xcode.app.
    cat >"$STUBS/xcode-select" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -p ] && { echo "${STUB_DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"; exit 0; }
exit 0
EOF
    cat >"$STUBS/xcodebuild" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -version) echo "xcode-select: error: tool 'xcodebuild' requires Xcode" >&2; exit 1 ;;
    -checkFirstLaunchStatus) exit "${STUB_FIRST_LAUNCH_RC:-1}" ;;
    -showsdks) printf '%s\n' "${STUB_SDKS:-}" ;;
esac
exit 0
EOF
    cat >"$STUBS/xcrun" <<'EOF'
#!/usr/bin/env bash
echo "== Runtimes =="
printf '%s' "${STUB_RUNTIMES:-}" | sed '/^$/d'
EOF
    cat >"$STUBS/xcodes" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$MARKER"
EOF
    # Never let a test reach the real sudo.
    cat >"$STUBS/sudo" <<'EOF'
#!/usr/bin/env bash
case "$1" in -v | -n) exit 0 ;; esac
exit 0
EOF
    chmod +x "$STUBS"/*
    PATH="$STUBS:$PATH"
    export PATH XCODE_APPS_DIR="$APPS"
}

# assert_no_download — the invariant. Named so a failure reads as what it is.
assert_no_download() {
    if [ -f "$MARKER" ]; then
        echo "xcodes install was invoked without consent: $(cat "$MARKER")"
        return 1
    fi
}

# ─── The invariant, headless ────────────────────────────────────────────────────
# Whether /dev/tty is openable under the test runner decides *which* guard fires
# (the upfront refusal or the EOF decline), and that varies by environment — so
# assert the property both guards exist to protect, not the specific message.

@test "headless with no YES=1: nothing is downloaded" {
    run bash "$SCRIPT" </dev/null
    assert_no_download
    # Either refused upfront (1) or declined at the prompt (0) — never a
    # pretended success after a download.
    [ "$status" -eq 1 ] || [ "$status" -eq 0 ]
}

@test "headless: the run says why, rather than failing silently" {
    run bash "$SCRIPT" </dev/null
    [[ "$output" == *"no terminal to confirm on"* ]] || [[ "$output" == *"skipped"* ]]
}

@test "--check never downloads and exits non-zero when not ready" {
    run bash "$SCRIPT" --check </dev/null
    assert_no_download
    [ "$status" -eq 1 ]
    [[ "$output" == *"no Xcode.app"* ]]
}

@test "--help never downloads" {
    run bash "$SCRIPT" --help </dev/null
    assert_no_download
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: chezxcode"* ]]
}

@test "an unknown flag is rejected and downloads nothing" {
    run bash "$SCRIPT" --wat </dev/null
    assert_no_download
    [ "$status" -eq 1 ]
}

# ─── DRY_RUN ───────────────────────────────────────────────────────────────────

@test "DRY_RUN prints the xcodes command it would run, without running it" {
    run env DRY_RUN=1 bash "$SCRIPT" </dev/null
    assert_no_download
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry-run \$ xcodes install --latest"* ]]
    # A preview must never claim the work happened.
    [[ "$output" == *"would install Xcode"* ]]
    [[ "$output" == *"nothing was changed"* ]]
}

@test "DRY_RUN never reaches sudo -v" {
    # The upfront sudo prompt is skipped entirely under DRY_RUN, so a preview
    # can run in a context with no admin rights at all.
    run env DRY_RUN=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
}

# ─── Opting out of the runtime specifically ────────────────────────────────────

@test "SKIP_RUNTIME=1 skips step 5 and says how to fetch it later" {
    # Xcode itself present and healthy, so only step 5 is outstanding.
    export STUB_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    export STUB_FIRST_LAUNCH_RC=0
    export STUB_SDKS="	Simulator - iOS 26.5          	-sdk iphonesimulator26.5"
    export STUB_RUNTIMES=""
    run env SKIP_RUNTIME=1 YES=1 DRY_RUN=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP_RUNTIME=1"* ]]
    [[ "$output" == *"xcodebuild -downloadPlatform iOS"* ]]
    # Step 5 skipped must not be reported as a completed download.
    [[ "$output" != *"[5/5]"*"✓ installed"* ]]
}

# ─── Already-ready short circuit ───────────────────────────────────────────────

@test "a ready machine exits early without prompting or downloading" {
    export STUB_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    export STUB_FIRST_LAUNCH_RC=0
    export STUB_SDKS="	Simulator - iOS 26.5          	-sdk iphonesimulator26.5"
    export STUB_RUNTIMES="iOS 26.5 (26.5 - 23F79) - com.apple.CoreSimulator.SimRuntime.iOS-26-5"
    # xcodebuild -version must succeed for xcode_ready; override the failing stub.
    cat >"$STUBS/xcodebuild" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -version) echo "Xcode 26.6" ;;
    -checkFirstLaunchStatus) exit 0 ;;
    -showsdks) printf '%s\n' "${STUB_SDKS:-}" ;;
esac
exit 0
EOF
    chmod +x "$STUBS/xcodebuild"
    run bash "$SCRIPT" </dev/null
    assert_no_download
    [ "$status" -eq 0 ]
    [[ "$output" == *"already ready"* ]]
}
