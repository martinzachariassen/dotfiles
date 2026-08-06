#!/usr/bin/env bats
# Tests for scripts/bin/macos-defaults.sh's sudo-keeper dedup: under a chezmoi
# apply, run_before_00-sudo-cache already keeps sudo warm for the whole run
# (scripts/lib/sudo.sh), so macos-defaults.sh must skip spawning a second
# keeper when told the caller already has one running.
#
# macos-defaults.sh itself calls macOS-only commands (defaults, sw_vers,
# chflags) and can't be executed end-to-end here; these are static checks,
# same approach chezmoi-scripts.bats uses for guards it can't exercise on
# Linux.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    MD="$REPO_ROOT/scripts/bin/macos-defaults.sh"
    HOOK="$REPO_ROOT/src/.chezmoiscripts/run_onchange_after_04-macos-defaults.sh.tmpl"
}

@test "macos-defaults.sh sources the shared sudo-keeper lib" {
    grep -qF '. "$_MD_DIR/../lib/sudo.sh"' "$MD"
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
@test "macos-defaults.sh fails loudly when log.sh is missing" {
    iso="$(mktemp -d)"
    mkdir -p "$iso/scripts/bin" # no scripts/lib ⇒ both siblings unreachable
    cp "$MD" "$iso/scripts/bin/macos-defaults.sh"
    run bash "$iso/scripts/bin/macos-defaults.sh"
    rm -rf "$iso"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]]
    [[ "$output" == *"log.sh"* ]]
}

@test "macos-defaults.sh fails loudly when sudo.sh is missing but log.sh is present" {
    iso="$(mktemp -d)"
    mkdir -p "$iso/scripts/bin" "$iso/scripts/lib"
    cp "$MD" "$iso/scripts/bin/macos-defaults.sh"
    cp "$REPO_ROOT/scripts/lib/log.sh" "$iso/scripts/lib/log.sh"
    run bash "$iso/scripts/bin/macos-defaults.sh"
    rm -rf "$iso"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]]
    [[ "$output" == *"sudo.sh"* ]]
}
