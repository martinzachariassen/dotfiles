#!/usr/bin/env bats
# brew-failure-report.bats — what an apply says when `brew bundle` fails.
#
# On a real fresh install two packages failed and the report was useless: it
# printed the last 15 log lines, which were four successful installs and a
# "`brew bundle` complete!" banner, then advised "usually a transient download.
# Re-run chezup". One of the two failures was permanent (a formula that needs a
# full Xcode.app in order to build), so that advice was an infinite loop.
#
# These pin the two parsers that turn the captured log and Homebrew's own state
# back into an answer.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LOG="$REPO_ROOT/scripts/lib/log.sh"
    BP="$REPO_ROOT/scripts/lib/brew-progress.sh"
    HOOK="$REPO_ROOT/src/.chezmoiscripts/run_after_02-brew-bundle.sh.tmpl"
    FIX="$(mktemp -d)"
}
teardown() { rm -rf "$FIX"; }

lib() { printf 'export LC_ALL=en_US.UTF-8; . "%s"; . "%s"; ui_init_logging;' "$LOG" "$BP"; }

# ─── brew_error_lines ─────────────────────────────────────────────────────────

@test "the error is surfaced even when successes follow it in the log" {
    cat >"$FIX/brew.log" <<'EOF'
Using swiftlint
Installing xcodes from xcodesorg/made
error: xcbuild executable at '/Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild' does not exist or is not executable
make: *** [xcodes] Error 1
Using fastlane
Installing mas
`brew bundle` complete! 17 Brewfile dependencies now installed.
EOF
    run bash -c "$(lib) brew_error_lines '$FIX/brew.log'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"xcbuild executable"* ]]
    # The old `tail -15` showed these instead of the error.
    [[ "$output" != *"brew bundle\` complete"* ]]
}

@test "Error: lines are matched regardless of case" {
    printf 'Using jq\nError: docker-desktop: Failed to link binary\n' >"$FIX/brew.log"
    run bash -c "$(lib) brew_error_lines '$FIX/brew.log'"
    [[ "$output" == *"Failed to link binary"* ]]
}

@test "a log with no error line still shows something to read" {
    printf 'Using jq\nUsing fd\nUsing ripgrep\n' >"$FIX/brew.log"
    run bash -c "$(lib) brew_error_lines '$FIX/brew.log' 2"
    [ -n "$output" ]
    [[ "$output" == *"ripgrep"* ]]
}

@test "the number of surfaced error lines is capped" {
    for i in $(seq 1 40); do printf 'Error: failure %s\n' "$i"; done >"$FIX/brew.log"
    run bash -c "$(lib) brew_error_lines '$FIX/brew.log' 5"
    [ "${#lines[@]}" -eq 5 ]
    # Newest last — the most recent failure must be visible.
    [[ "${lines[4]}" == *"failure 40"* ]]
}

@test "a missing log file is not fatal" {
    run bash -c "$(lib) brew_error_lines '$FIX/nope.log'"
    [ "$status" -eq 0 ]
}

# ─── brew_unmet_entries ───────────────────────────────────────────────────────
# `brew bundle check` writes to stderr and prefixes each line with a non-ASCII
# arrow. Both bit earlier versions of this parser, so both are pinned here with
# a stub rather than a live brew.

@test "unmet entries are parsed off stderr, arrow prefix and all" {
    mkdir -p "$FIX/stubs"
    cat >"$FIX/stubs/brew" <<'EOF'
#!/usr/bin/env bash
cat >&2 <<'OUT'
brew bundle can't satisfy your Brewfile's dependencies.
→ Cask docker-desktop needs to be installed.
→ Formula xcodesorg/made/xcodes needs to be installed.
Satisfy missing dependencies with `brew bundle install`.
OUT
exit 1
EOF
    chmod +x "$FIX/stubs/brew"
    run env PATH="$FIX/stubs:$PATH" bash -c "$(lib) brew_unmet_entries /dev/null"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "Cask docker-desktop" ]
    [ "${lines[1]}" = "Formula xcodesorg/made/xcodes" ]
    # The surrounding prose must not leak into the list.
    [ "${#lines[@]}" -eq 2 ]
}

@test "a satisfied Brewfile yields no entries" {
    mkdir -p "$FIX/stubs"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$FIX/stubs/brew"
    chmod +x "$FIX/stubs/brew"
    run env PATH="$FIX/stubs:$PATH" bash -c "$(lib) brew_unmet_entries /dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── the hook wires them up ───────────────────────────────────────────────────

@test "the hook reports named packages and real errors, not a blind tail" {
    grep -q 'brew_unmet_entries' "$HOOK"
    grep -q 'brew_error_lines' "$HOOK"
    ! grep -q 'tail -n 15' "$HOOK"
}

@test "the hook no longer calls every failure transient" {
    ! grep -q 'Usually a transient download' "$HOOK"
}

@test "the failure log is copied somewhere macOS will not purge" {
    # mktemp lands in /var/folders, which is cleaned periodically — the printed
    # "full log:" path was routinely dead by the time anyone looked.
    grep -q '.local/state/dotfiles' "$HOOK"
}

@test "a failed apply still exits 0 so the rest of the apply continues" {
    grep -A2 'error above is the real reason' "$HOOK" | grep -q 'exit 0'
}
