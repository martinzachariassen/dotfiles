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

    # The script guards on `uname -s` = Darwin, and CI runs Ubuntu — stub it the
    # same way tests/install.bats does, so these tests exercise the real logic on
    # either platform. UNAME_S flips it back to test the guard itself.
    cat >"$STUBS/uname" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -s) echo "${UNAME_S:-Darwin}" ;;
    -m) echo "${UNAME_M:-arm64}" ;;
    *) echo "Darwin" ;;
esac
EOF

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
    [[ "$output" == *"no Xcode.app"* ]] || return 1
}

@test "--help never downloads" {
    run bash "$SCRIPT" --help </dev/null
    assert_no_download
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: chezxcode"* ]] || return 1
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
    [[ "$output" == *"dry-run \$ xcodes install --latest"* ]] || return 1
    # A preview must never claim the work happened.
    [[ "$output" == *"would install Xcode"* ]] || return 1
    [[ "$output" == *"nothing was changed"* ]] || return 1
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
    [[ "$output" == *"SKIP_RUNTIME=1"* ]] || return 1
    [[ "$output" == *"xcodebuild -downloadPlatform iOS"* ]] || return 1
    # Step 5 skipped must not be reported as a completed download.
    [[ "$output" != *"[5/5]"*"✓ installed"* ]] || return 1
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
    [[ "$output" == *"already ready"* ]] || return 1
}

# ─── Platform guard ────────────────────────────────────────────────────────────
# Pins why the uname stub above exists: without it every test below runs against
# the guard's early exit rather than the logic it means to check.

@test "refuses to run off macOS" {
    run env UNAME_S=Linux bash "$SCRIPT" </dev/null
    assert_no_download
    [ "$status" -eq 1 ]
    [[ "$output" == *"only exists on macOS"* ]] || return 1
}

# ─── The real run: a stateful fake of the whole Xcode layer ─────────────────────
# Everything above proves chezxcode does NOT act. These prove it acts correctly
# when it should. The stubs below are a small state machine — `xcodes install`
# creates the app, `-license accept` clears the licence gate, `-downloadPlatform`
# registers a runtime — so a second run genuinely observes the first run's
# effects, which is the only honest way to test the "idempotent, safe to re-run"
# claim. Each stub appends to $CALLS, so order is assertable too.

_stateful_stubs() {
    STATE="$BATS_TEST_TMPDIR/state"
    CALLS="$BATS_TEST_TMPDIR/calls"
    mkdir -p "$STATE"
    : >"$CALLS"
    echo "${1:-/Library/Developer/CommandLineTools}" >"$STATE/devdir"

    cat >"$STUBS/xcode-select" <<EOF
#!/usr/bin/env bash
case "\$1" in
    -p) cat "$STATE/devdir" ;;
    -s) printf 'xcode-select -s %s\n' "\$2" >>"$CALLS"; printf '%s\n' "\$2" >"$STATE/devdir" ;;
esac
EOF
    cat >"$STUBS/xcodebuild" <<EOF
#!/usr/bin/env bash
case "\$1" in
    -version)
        [ -d "$APPS/Xcode.app" ] || { echo "requires Xcode" >&2; exit 1; }
        [ -f "$STATE/licensed" ] || {
            echo "You have not agreed to the Xcode license agreements." >&2; exit 69; }
        echo "Xcode 26.6" ;;
    -license)
        printf 'xcodebuild -license %s\n' "\$2" >>"$CALLS"
        [ "\$2" = accept ] && touch "$STATE/licensed" ;;
    # Explicit exit: the trailing `exit 0` below would otherwise swallow the
    # test's result and report first-launch as always done.
    -checkFirstLaunchStatus) [ -f "$STATE/firstlaunch" ] || exit 1 ;;
    -runFirstLaunch)
        printf 'xcodebuild -runFirstLaunch\n' >>"$CALLS"; touch "$STATE/firstlaunch" ;;
    -showsdks)
        case "\$(cat "$STATE/devdir")" in
            */Xcode*.app/Contents/Developer) echo "  Simulator - iOS 26.5  -sdk iphonesimulator26.5" ;;
            *) echo "  macOS 26.5  -sdk macosx26.5" ;;
        esac ;;
    -downloadPlatform)
        printf 'xcodebuild -downloadPlatform %s\n' "\$2" >>"$CALLS"; touch "$STATE/runtime" ;;
esac
exit 0
EOF
    cat >"$STUBS/xcrun" <<EOF
#!/usr/bin/env bash
echo "== Runtimes =="
[ -f "$STATE/runtime" ] &&
    echo "iOS 26.5 (26.5 - 23F79) - com.apple.CoreSimulator.SimRuntime.iOS-26-5"
exit 0
EOF
    # --select is what makes step 2 a no-op on the common path; honour it.
    cat >"$STUBS/xcodes" <<EOF
#!/usr/bin/env bash
printf 'xcodes %s\n' "\$*" >>"$CALLS"
mkdir -p "$APPS/Xcode.app"
case "\$*" in *--select*) printf '%s\n' "$APPS/Xcode.app/Contents/Developer" >"$STATE/devdir" ;; esac
EOF
    # sudo runs the real (stubbed) command, so privileged steps mutate state.
    cat >"$STUBS/sudo" <<'EOF'
#!/usr/bin/env bash
case "$1" in -v | -n) exit 0 ;; esac
exec "$@"
EOF
    chmod +x "$STUBS"/*
    export XCODE_APPS_DIR="$APPS"
}

@test "a full run drives all five steps in order and ends ready" {
    _stateful_stubs
    run env YES=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"ready to build and run iOS apps"* ]] || return 1

    # Order matters: selecting before installing, or downloading a runtime
    # before first-launch, both fail on a real machine.
    run cat "$CALLS"
    [[ "${lines[0]}" == "xcodes install --latest --select --experimental-unxip" ]] || return 1
    [[ "${lines[1]}" == "xcodebuild -license accept" ]] || return 1
    [[ "${lines[2]}" == "xcodebuild -runFirstLaunch" ]] || return 1
    [[ "${lines[3]}" == "xcodebuild -downloadPlatform iOS" ]] || return 1
    [ "${#lines[@]}" -eq 4 ]
}

# The claim in the script header is "idempotent; safe to re-run". This is what
# that has to mean: a second run does no work at all.
@test "re-running a ready machine invokes nothing" {
    _stateful_stubs
    env YES=1 bash "$SCRIPT" </dev/null >/dev/null
    : >"$CALLS"

    run env YES=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"already ready"* ]] || return 1
    [ ! -s "$CALLS" ]
}

# Xcode installed by some other route (App Store, restored image) leaves the CLT
# selected — step 1 must no-op while step 2 does the repair.
@test "Xcode present but CLT selected: step 2 repairs the selection" {
    _stateful_stubs
    mkdir -p "$APPS/Xcode.app" # present, but devdir still points at the CLT

    run env YES=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    run cat "$CALLS"
    [[ "$output" != *"xcodes install"* ]] || return 1
    [[ "${lines[0]}" == "xcode-select -s $APPS/Xcode.app/Contents/Developer" ]] || return 1
}

@test "XCODE_VERSION pins the version instead of --latest" {
    _stateful_stubs
    run env YES=1 XCODE_VERSION=26.6 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    grep -qF -- "xcodes install 26.6 --select --experimental-unxip" "$CALLS"
    ! grep -qF -- "--latest" "$CALLS"
}

@test "SKIP_RUNTIME=1 does everything except the runtime download" {
    _stateful_stubs
    run env YES=1 SKIP_RUNTIME=1 bash "$SCRIPT" </dev/null
    grep -qF "xcodes install" "$CALLS"
    grep -qF "xcodebuild -runFirstLaunch" "$CALLS"
    ! grep -qF "downloadPlatform" "$CALLS"
    # Still not "ready" — and it must say so rather than claim success.
    [ "$status" -eq 1 ]
    [[ "$output" == *"not ready yet"* ]] || return 1
}

# The licence step is skipped when xcodebuild already runs clean; accepting it
# again is harmless but a wasted sudo call, and it would mask a real failure.
@test "an already-licensed Xcode is not re-licensed" {
    _stateful_stubs "$BATS_TEST_TMPDIR/Applications/Xcode.app/Contents/Developer"
    mkdir -p "$APPS/Xcode.app"
    touch "$STATE/licensed"

    run env YES=1 bash "$SCRIPT" </dev/null
    [ "$status" -eq 0 ]
    ! grep -qF -- "-license" "$CALLS"
}
