#!/usr/bin/env bats
# Tests for features/macos/cli.sh's sudo-keeper dedup: under a chezmoi
# apply, run_before_00-sudo-cache already keeps sudo warm for the whole run
# (core/sudo.sh), so macos-defaults.sh must skip spawning a second
# keeper when told the caller already has one running.
#
# macos-defaults.sh itself calls macOS-only commands (defaults, sw_vers,
# chflags) and can't be executed end-to-end here; these are static checks,
# same approach chezmoi-scripts.bats uses for guards it can't exercise on
# Linux.

setup() {
    load '../../../core/testing/helper'
    MD="$REPO_ROOT/features/macos/cli.sh"
    HOOK="$REPO_ROOT/src/.chezmoiscripts/run_onchange_after_04-macos-defaults.sh.tmpl"
}

@test "macos-defaults.sh sources the shared sudo-keeper lib" {
    grep -qF '. "$_MD_DIR/../../core/sudo.sh"' "$MD"
}

@test "macos-defaults.sh skips its own keeper when the caller already keeps sudo warm" {
    grep -qF 'DOTFILES_SUDO_KEPT_WARM' "$MD"
    grep -qF 'sudo_keep_warm "$$"' "$MD"
}

@test "macos-defaults.sh no longer inlines a second sudo-keeper loop" {
    ! grep -qF 'PARENT_PID=$$' "$MD"
}

@test "the macos-defaults hook marks sudo as already kept warm before invoking the script" {
    grep -qF 'DOTFILES_SUDO_KEPT_WARM=1 bash' "$HOOK"
}

# The guard block runs before any macOS-only command, so it's exercisable on Linux.
@test "macos-defaults.sh fails loudly when core/ui.sh is missing" {
    iso="$(mktemp -d)"
    mkdir -p "$iso/features/macos" # no core/ ⇒ both helpers unreachable
    cp "$MD" "$iso/features/macos/cli.sh"
    run bash "$iso/features/macos/cli.sh"
    rm -rf "$iso"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || return 1
    [[ "$output" == *"ui.sh"* ]] || return 1
}

@test "macos-defaults.sh fails loudly when sudo.sh is missing but core/ui.sh is present" {
    iso="$(mktemp -d)"
    mkdir -p "$iso/features/macos" "$iso/core"
    cp "$MD" "$iso/features/macos/cli.sh"
    cp "$REPO_ROOT/core/ui.sh" "$iso/core/ui.sh"
    run bash "$iso/features/macos/cli.sh"
    rm -rf "$iso"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || return 1
    [[ "$output" == *"sudo.sh"* ]] || return 1
}

# run_before_00-sudo-cache is explicitly allowed to give up on caching sudo, so
# arriving here cold is a supported state. Under `set -e` a bare `sudo -v` would
# then kill the script, the hook, and the rest of the apply.
@test "macos-defaults.sh treats an unobtainable sudo as a skip, not a failure" {
    grep -qE '^\s*if ! sudo -v' "$MD"
    grep -qF 'skipping macOS defaults' "$MD"
    # No bare `sudo -v` left at the start of a line under set -e.
    ! grep -qE '^\s*sudo -v ' "$MD"
}
