#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_xcode() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# The Xcode layer an apply cannot install. `brew bundle check` already covers
# the swiftlint/xcodes/sweetpad tier; none of that can build an iOS app, so
# this checks what is underneath it. Gated on appleDev by the registry.

doctor_xcode() {
    # Only meaningful with appleDev on. `brew bundle check` above already covers the
    # swiftlint/xcodes/sweetpad tier; none of it can build an iOS app, so this
    # section checks the Xcode layer underneath — which nothing in an apply installs.
    section "Xcode / iOS (appleDev)"
    if ! command -v xcode_ready >/dev/null 2>&1; then
        warn "features/xcode/probe.sh missing — Xcode checks skipped"
    elif [ -z "$(xcode_app_path || true)" ]; then
        # One fail, not six: without Xcode.app every check below fails for the
        # same reason, and six red lines read as six problems.
        fail "no Xcode.app — install.sh only installs the Command Line Tools. Run: chezxcode"
    else
        pass "Xcode installed: $(xcode_app_path)"
        if xcode_selected_is_full; then
            pass "active developer dir: $(xcode-select -p)"
        else
            fail "xcode-select points at $(xcode-select -p 2>/dev/null || echo none), not Xcode.app — run: chezxcode"
        fi
        if xcode_build_works; then
            pass "xcodebuild runs: $(xcodebuild -version 2>/dev/null | head -1)"
        elif xcode_license_pending; then
            fail "Xcode licence not accepted — run: chezxcode"
        else
            fail "xcodebuild fails — run: chezxcode"
        fi
        if xcode_first_launch_done; then
            pass "first-launch components installed"
        else
            fail "Xcode first-launch components pending — run: chezxcode"
        fi
        if xcode_has_ios_sdk; then
            pass "iOS Simulator SDK present"
        else
            fail "no iOS Simulator SDK — run: chezxcode"
        fi
        # Separate downloads since Xcode 16, so a complete Xcode routinely has
        # none and every iOS simulator shows as "Unavailable".
        if xcode_has_ios_runtime; then
            pass "iOS simulator runtime: $(xcode_ios_runtimes_summary)"
        else
            fail "no iOS simulator runtime — nothing to run an app on. Run: chezxcode"
        fi
    fi
    for tool in swiftlint swiftformat xcodegen xcode-build-server xcbeautify; do
        if command -v "$tool" >/dev/null 2>&1; then
            pass "$tool on PATH"
        else
            warn "$tool missing — run: chezapply"
        fi
    done
    # SwiftLint doesn't ascend to $HOME, so the config only takes effect when
    # passed with --config; its absence means projects fall back to bare defaults.
    if [ -f "$HOME/.config/swiftlint/config.yml" ]; then
        pass "~/.config/swiftlint/config.yml present"
    else
        warn "~/.config/swiftlint/config.yml missing — run: chezapply"
    fi
    if [ -f "$HOME/.swiftformat" ]; then
        pass "~/.swiftformat present"
    else
        warn "~/.swiftformat missing — run: chezapply"
    fi
}
