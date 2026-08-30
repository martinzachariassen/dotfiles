#!/usr/bin/env bash
# xcode.sh — read-only probes for the Xcode layer the appleDev module depends on.
# Shared by features/xcode/cli.sh (which fixes what these report) and doctor.sh
# (which only reports), so the two can never disagree about what "ready" means.
#
# Why a whole file for five checks: `brew bundle` gets you swiftlint/xcodes/
# sweetpad, but none of that can build an iOS app. Xcode.app itself, the selected
# developer dir, the licence, first-launch components, and a downloaded simulator
# runtime are five separate pieces of state, each with its own failure mode, and
# install.sh only ever installs the Command Line Tools.
# shellcheck disable=SC2034,SC2329

[ -n "${__DOTFILES_XCODE_SH:-}" ] && return 0
__DOTFILES_XCODE_SH=1

# xcode_app_path — path to the Xcode.app this machine should use, or empty.
# Prefers whatever `xcode-select` already points at so we never silently
# disagree with a deliberate choice; otherwise takes the first one in
# /Applications.
xcode_app_path() {
    local dev app
    dev="$(xcode-select -p 2>/dev/null || true)"
    case "$dev" in
        */Xcode*.app/Contents/Developer)
            printf '%s\n' "${dev%/Contents/Developer}"
            return 0
            ;;
    esac
    # XCODE_APPS_DIR is a test seam — xcodes always installs into /Applications.
    local apps="${XCODE_APPS_DIR:-/Applications}"
    for app in "$apps"/Xcode.app "$apps"/Xcode-*.app "$apps"/Xcode*.app; do
        if [ -d "$app" ]; then
            printf '%s\n' "$app"
            return 0
        fi
    done
    return 1
}

# xcode_selected_is_full — 0 when `xcode-select -p` resolves inside an Xcode.app.
# The Command Line Tools satisfy `xcode-select -p` too, which is exactly the trap:
# install.sh installs the CLT first, so a machine can look configured while
# xcodebuild still resolves to the CLT stub with no iOS SDK behind it.
xcode_selected_is_full() {
    case "$(xcode-select -p 2>/dev/null || true)" in
        */Xcode*.app/Contents/Developer) return 0 ;;
        *) return 1 ;;
    esac
}

# xcode_build_works — 0 when `xcodebuild -version` runs clean. False for every
# reason at once (no Xcode, CLT selected, licence pending); pair it with the
# more specific probes below to say which.
xcode_build_works() {
    xcodebuild -version >/dev/null 2>&1
}

# xcode_license_pending — 0 when xcodebuild is blocked on the licence agreement.
# Apple exposes no query for this: the agreement check is the first thing
# xcodebuild does and it reports refusal on stderr, so matching that text is the
# only signal available.
#
# The output is captured before grepping rather than piped into it. Callers run
# under `set -o pipefail`, where `xcodebuild … | grep -q` yields xcodebuild's
# exit code (69, EX_UNAVAILABLE, in exactly the licence-pending case) instead of
# grep's — so the piped form reports "no licence problem" precisely when there
# is one.
xcode_license_pending() {
    local out
    out="$(xcodebuild -version 2>&1 || true)"
    printf '%s\n' "$out" | grep -qiE 'license|licence'
}

# xcode_first_launch_done — 0 when no bundled component install is outstanding.
# `-checkFirstLaunchStatus` is Apple's own query and exits non-zero when
# `-runFirstLaunch` still has work to do.
xcode_first_launch_done() {
    xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1
}

# xcode_has_ios_sdk — 0 when an iOS Simulator SDK is present. Absent whenever the
# CLT are selected, which is the cheapest proof that the selected toolchain
# cannot build for iOS at all.
xcode_has_ios_sdk() {
    local out
    out="$(xcodebuild -showsdks 2>/dev/null || true)" # capture: see xcode_license_pending
    printf '%s\n' "$out" | grep -q 'iphonesimulator'
}

# xcode_ios_runtimes — installed, usable iOS simulator runtimes, one per line.
# Since Xcode 16 these ship as separate multi-gigabyte downloads, so a complete
# Xcode install routinely has none: `simctl list runtimes` then prints its
# header and nothing else, and every iOS device profile reports "Unavailable".
# Runtimes registered but not downloaded are listed with an "(unavailable…)"
# suffix, so they are filtered out rather than counted.
xcode_ios_runtimes() {
    local out
    out="$(xcrun simctl list runtimes 2>/dev/null || true)" # capture: see xcode_license_pending
    printf '%s\n' "$out" | grep -E '^iOS [0-9]' | grep -viE 'unavailable' || true
}

xcode_has_ios_runtime() {
    [ -n "$(xcode_ios_runtimes)" ]
}

# xcode_ios_runtimes_summary — "iOS 26.5, iOS 18.6" for one-line reporting.
# Not `paste -sd', '`: BSD paste treats a multi-character -d as a cycling list
# of delimiters, so that joins with ',' and ' ' alternately.
xcode_ios_runtimes_summary() {
    xcode_ios_runtimes | sed 's/ (.*//' | tr '\n' '|' | sed -e 's/|$//' -e 's/|/, /g'
}

# xcode_ready — 0 only when all five pieces hold, i.e. an iOS app can actually be
# built and run on a simulator from this machine.
xcode_ready() {
    xcode_app_path >/dev/null &&
        xcode_selected_is_full &&
        xcode_build_works &&
        xcode_first_launch_done &&
        xcode_has_ios_sdk &&
        xcode_has_ios_runtime
}
