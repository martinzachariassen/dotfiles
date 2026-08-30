#!/usr/bin/env bash
# xcode.sh — bring the Xcode layer up to "can build and run an iOS app", backing
# the `chezxcode` verb. Idempotent; safe to re-run.
#
# Deliberately NOT a chezmoi apply hook. `xcodes install` authenticates against
# an Apple ID with 2FA, so it cannot run unattended, and the downloads are tens
# of gigabytes — parking that inside `chezmoi apply` would stall an otherwise
# silent apply on an interactive prompt and blow past the runtime install.sh
# promises. Same shape as `chezsign`: an interactive step the setup points you
# at, with `chezdoctor` staying red until it's done.
#
# Env: DRY_RUN=1 print each command instead of running it.
#      YES=1 don't ask before the two large downloads.
#      XCODE_VERSION=26.6 install that version instead of --latest.
#      SKIP_RUNTIME=1 stop after first-launch; don't fetch a simulator runtime.

set -uo pipefail

DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${YES:-0}"
XCODE_VERSION="${XCODE_VERSION:-}"
SKIP_RUNTIME="${SKIP_RUNTIME:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$_DIR/../../core/ui.sh" ]; then
    printf 'chezxcode: missing %s\n' "$_DIR/../../core/ui.sh" >&2
    exit 1
fi
# shellcheck source=../../core/ui.sh
. "$_DIR/../../core/ui.sh"
# shellcheck source=../../core/dry-run.sh
. "$_DIR/../../core/dry-run.sh"
# shellcheck source=../../core/sudo.sh
. "$_DIR/../../core/sudo.sh"
# shellcheck source=../lib/xcode.sh
. "$_DIR/../lib/xcode.sh"
# shellcheck source=../lib/xcodes.sh
. "$_DIR/../lib/xcodes.sh"

usage() {
    echo "usage: chezxcode [--check]"
    echo "  (no arg)   install/repair Xcode until an iOS app can be built and run"
    echo "  --check    report the five checks and exit; changes nothing"
    echo
    echo "Env: DRY_RUN=1 · YES=1 · XCODE_VERSION=26.6 · SKIP_RUNTIME=1"
}

CHECK_ONLY=0
case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
    --check | -c) CHECK_ONLY=1 ;;
    "") ;;
    *)
        usage >&2
        exit 1
        ;;
esac

[ "$(uname -s)" = "Darwin" ] || {
    ui_init_logging
    fail "Xcode only exists on macOS."
    exit 1
}

# ─── --check: read-only report ───────────────────────────────────────────────
if [ "$CHECK_ONLY" = "1" ]; then
    ui_init_status
    echo
    printf '%s%s%s %sXcode readiness%s\n' "$BOLD" "$BLUE" "$NODE" "$BOLD" "$RESET"
    app="$(xcode_app_path || true)"
    if [ -n "$app" ]; then
        s_pass "Xcode installed: $app"
    else
        s_fail "no Xcode.app — run: chezxcode"
    fi
    if xcode_selected_is_full; then
        s_pass "active developer dir: $(xcode-select -p)"
    else
        s_fail "active developer dir is $(xcode-select -p 2>/dev/null || echo none) (not a full Xcode) — run: chezxcode"
    fi
    if xcode_build_works; then
        s_pass "xcodebuild runs"
    else
        s_fail "xcodebuild fails — run: chezxcode"
    fi
    if xcode_first_launch_done; then
        s_pass "first-launch components installed"
    else
        s_fail "first-launch components pending — run: chezxcode"
    fi
    if xcode_has_ios_sdk; then
        s_pass "iOS Simulator SDK present"
    else
        s_fail "no iOS Simulator SDK — run: chezxcode"
    fi
    if xcode_has_ios_runtime; then
        s_pass "iOS simulator runtime(s): $(xcode_ios_runtimes_summary)"
    else
        s_fail "no iOS simulator runtime downloaded — run: chezxcode"
    fi
    echo
    if xcode_ready; then
        exit 0
    fi
    exit 1
fi

ui_init_steps 5

on_interrupt() {
    printf '\033[?25h\n' >/dev/tty 2>/dev/null || true
    warn "aborted — anything already installed is kept; re-run chezxcode to continue."
    exit 130
}
trap on_interrupt INT TERM

echo
printf '%s%s%s  %sXcode and the iOS toolchain%s\n' "$CYAN" "$NODE" "$RESET" "$BOLD" "$RESET"
explain \
    "Homebrew gave you swiftlint, xcodes, sweetpad and friends — none of which" \
    "can build an iOS app on their own. This adds the five pieces that can:" \
    "" \
    "  1. Xcode.app            the SDKs, Simulator.app and SourceKit-LSP" \
    "  2. Active toolchain     point xcode-select away from the Command Line Tools" \
    "  3. Licence              accept it once, or xcodebuild refuses to run" \
    "  4. First-launch         Xcode's bundled components" \
    "  5. Simulator runtime    a separate download since Xcode 16" \
    "" \
    "Budget ~40 GB and up to an hour on a fresh Mac, almost all downloading." \
    "Every step checks first and skips what is already done."

if xcode_ready; then
    echo
    ok "already ready — Xcode $(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}') at $(xcode_app_path)"
    dim "    runtimes: $(xcode_ios_runtimes_summary)"
    exit 0
fi

# confirm PROMPT — 0 to proceed. A terminal is guaranteed by the gate below, so
# this never has to decide what a missing one means.
confirm() {
    # A dry run downloads nothing, so there is nothing to consent to — and the
    # preview has to work headless, where /dev/tty cannot be written at all.
    [ "$DRY_RUN" = "1" ] && return 0
    [ "$ASSUME_YES" = "1" ] && return 0
    printf '%s  %s [Y/n] ' "$(line_prefix)" "$1" >/dev/tty
    # A failed read is EOF (stdin closed, terminal went away), not a keypress —
    # never take it as consent for a multi-gigabyte download. A *successful*
    # empty read is someone pressing Enter, which the [Y/n] default does accept.
    IFS= read -r reply </dev/tty || return 1
    case "$reply" in
        n | N | no | NO) return 1 ;;
        *) return 0 ;;
    esac
}

# Fail closed with no terminal to ask on: every remaining step either prompts or
# starts a multi-gigabyte download, and chezclean sets the precedent that a verb
# with a confirm gate does nothing at all when it can't reach one. YES=1 is the
# deliberate way past it.
#
# The check opens /dev/tty rather than testing -r: under CI and some hook
# contexts it passes -e/-r and still fails to open, which previously let a ~40 GB
# download start unasked (after printing raw "Device not configured" errors).
if [ "$DRY_RUN" != "1" ] && [ "$ASSUME_YES" != "1" ] && ! { : </dev/tty; } 2>/dev/null; then
    fail "no terminal to confirm on — refusing to start a ~40 GB download unasked."
    info "run this from a terminal, or accept both downloads up front: YES=1 chezxcode"
    exit 1
fi

# step_applied VERB — close a step honestly under DRY_RUN, where nothing ran.
step_applied() {
    if [ "$DRY_RUN" = "1" ]; then
        step_skip "would $1"
    else
        step_ok "$2"
    fi
}

# Steps 2-5 all need root. Ask once here rather than four times mid-download,
# and keep the timestamp warm — the runtime fetch runs well past sudo's 5-minute
# cache, and a password prompt surfacing behind a progress bar looks like a hang.
if [ "$DRY_RUN" != "1" ]; then
    if ! sudo -v -p "Enter your macOS password (for Xcode setup): "; then
        fail "could not obtain admin access — Xcode setup needs it for steps 2-5."
        exit 1
    fi
    sudo_keep_warm "$$"
fi

# ─── 1. Xcode.app ────────────────────────────────────────────────────────────
step_begin "Xcode.app"
XCODE_APP="$(xcode_app_path || true)"
if [ -n "$XCODE_APP" ]; then
    step_ok "already installed — $XCODE_APP"
else
    explain \
        "xcodes downloads Xcode from Apple, so it needs your Apple ID and a 2FA" \
        "code. Nothing is stored by this repo — xcodes keeps the session in your" \
        "keychain. Use the same Apple ID you'll sign apps with."
    if ! confirm "Download and install Xcode ${XCODE_VERSION:-(latest)} (~40 GB)?"; then
        info "skipped — re-run chezxcode when you're ready."
        exit 0
    fi
    # Only now that the big download is consented to: `xcodes` itself can't come
    # from Homebrew — its formula builds from source and that build needs a full
    # Xcode.app, the very thing we're here to install. Fetch the upstream
    # prebuilt binary instead. See lib/xcodes.sh for the whole story.
    if ! xcodes_installed; then
        if [ "$DRY_RUN" = "1" ]; then
            dim "dry-run \$ install the xcodes CLI into $XCODES_BIN_DIR"
        else
            info "installing the xcodes CLI (not available as a working Homebrew bottle)"
            if ! xcodes_bootstrap; then
                step_fail "could not install the xcodes CLI — see the error above."
                exit 1
            fi
            ok "xcodes $(xcodes version 2>/dev/null || true) — $XCODES_BIN_DIR/xcodes"
        fi
    fi
    # --select lets xcodes point xcode-select at what it just installed; step 2
    # still runs, as the safety net for an Xcode that arrived some other way.
    if [ -n "$XCODE_VERSION" ]; then
        run xcodes install "$XCODE_VERSION" --select --experimental-unxip
    else
        run xcodes install --latest --select --experimental-unxip
    fi
    XCODE_APP="$(xcode_app_path || true)"
    if [ "$DRY_RUN" != "1" ] && [ -z "$XCODE_APP" ]; then
        step_fail "xcodes finished but no Xcode.app is present — check the output above."
        exit 1
    fi
    step_applied "install Xcode" "installed — $XCODE_APP"
fi

# ─── 2. Active developer directory ───────────────────────────────────────────
# install.sh installs the Command Line Tools as its very first step, so on a
# fresh Mac xcode-select points at them and keeps doing so after Xcode arrives.
# Everything downstream (iOS SDK, SourceKit-LSP, SweetPad) resolves through this.
step_begin "Active toolchain"
if xcode_selected_is_full; then
    step_ok "already selected — $(xcode-select -p)"
else
    was="$(xcode-select -p 2>/dev/null || echo none)"
    info "switching from $was"
    run sudo xcode-select -s "${XCODE_APP:-/Applications/Xcode.app}/Contents/Developer"
    step_applied "select Xcode" "selected — ${XCODE_APP:-/Applications/Xcode.app}/Contents/Developer"
fi

# ─── 3. Licence ──────────────────────────────────────────────────────────────
step_begin "Licence"
if xcode_build_works; then
    step_ok "already accepted"
elif xcode_license_pending; then
    explain "Accepting Apple's Xcode licence on your behalf — the same agreement" \
        "Xcode.app shows on first launch."
    run sudo xcodebuild -license accept
    step_applied "accept the licence" "accepted"
else
    step_skip "xcodebuild fails for some other reason — continuing; step 4 will report it."
fi

# ─── 4. First-launch components ──────────────────────────────────────────────
step_begin "First-launch components"
if xcode_first_launch_done; then
    step_ok "already installed"
else
    run sudo xcodebuild -runFirstLaunch
    if [ "$DRY_RUN" = "1" ]; then
        step_skip "would install first-launch components"
    elif ! xcode_first_launch_done; then
        step_fail "-runFirstLaunch ran but components are still pending — open Xcode.app once."
    else
        step_ok "installed"
    fi
fi

# ─── 5. iOS simulator runtime ────────────────────────────────────────────────
# Since Xcode 16 the runtimes are separate downloads. Without one, `simctl list
# runtimes` is empty, every iOS device shows as "Unavailable", and SweetPad's
# Destinations view has nothing to run on — while everything else looks healthy.
step_begin "iOS simulator runtime"
if [ "$SKIP_RUNTIME" = "1" ]; then
    step_skip "SKIP_RUNTIME=1 — skipped. Fetch later with: xcodebuild -downloadPlatform iOS"
elif xcode_has_ios_runtime; then
    step_ok "already installed — $(xcode_ios_runtimes_summary)"
elif ! confirm "Download the iOS simulator runtime (~10 GB)?"; then
    step_skip "skipped — fetch later with: xcodebuild -downloadPlatform iOS"
else
    run sudo xcodebuild -downloadPlatform iOS
    if [ "$DRY_RUN" = "1" ]; then
        step_skip "would download an iOS simulator runtime"
    elif ! xcode_has_ios_runtime; then
        step_fail "download finished but no runtime is registered — open Xcode → Settings → Components."
    else
        step_ok "installed"
    fi
fi

# ─── Verdict ─────────────────────────────────────────────────────────────────
echo
if [ "$DRY_RUN" = "1" ]; then
    info "dry run — nothing was changed."
    exit 0
fi
if xcode_ready; then
    ok "ready to build and run iOS apps."
    explain \
        "Signing is the one thing left, and it's genuinely manual: open Xcode →" \
        "Settings → Accounts, add your Apple ID, and pick the team on a target's" \
        "Signing & Capabilities tab. Xcode stores it per-project, not per-machine." \
        "" \
        "Verify any time with \`chezxcode --check\` or \`chezdoctor\`."
    exit 0
fi
fail "not ready yet — \`chezxcode --check\` lists what's still missing."
exit 1
