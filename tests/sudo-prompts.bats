#!/usr/bin/env bats
# sudo-prompts.bats — every password prompt has to explain itself.
#
# From a real fresh install: the overview promised "your macOS password (once,
# for Homebrew)" and then asked three times — install.sh, run_before_00, and
# macos-defaults. The first ask printed at column 0, outside the script's rail,
# and was immediately buried under twenty lines of raw `/usr/bin/sudo /bin/mkdir
# …` from Homebrew's own installer. The later two were bare bracketed prompts
# with no stated reason, appearing minutes apart.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    INSTALL="$REPO_ROOT/install.sh"
    SUDO_LIB="$REPO_ROOT/core/sudo.sh"
    MACOS="$REPO_ROOT/scripts/bin/macos-defaults.sh"
    HOOK="$REPO_ROOT/src/.chezmoiscripts/run_before_00-sudo-cache.sh.tmpl"
    BREW="$REPO_ROOT/src/.chezmoiscripts/run_after_02-brew-bundle.sh.tmpl"
}

# ─── install.sh ───────────────────────────────────────────────────────────────

@test "the overview no longer claims the password is asked for exactly once" {
    # It is asked again for casks and again for macOS defaults.
    ! grep -q 'your macOS password (once, for Homebrew)' "$INSTALL"
}

@test "the password prompt has a lead-in explaining the invisible typing" {
    grep -q 'nothing appears as you type' "$INSTALL"
}

@test "the lead-in survives QUIET=1" {
    # QUIET=1 drops prose via explain(); a password prompt must still announce
    # itself, so that one line goes through info() instead.
    grep -q 'info "macOS will ask for your login password' "$INSTALL"
}

@test "Touch ID is offered as the alternative" {
    grep -qi 'Touch ID' "$INSTALL"
}

@test "the wall of sudo lines Homebrew prints is pre-announced" {
    # Twenty raw "/usr/bin/sudo …" lines straight after a password prompt read
    # as a failure unless something says they are expected.
    grep -q 'prints each command it runs as administrator' "$INSTALL"
}

@test "the prompt names the account rather than being a bare string" {
    grep -q 'macOS password for %u' "$INSTALL"
}

@test "install.sh still dies when admin access is refused" {
    # The lead-in must not have swallowed the failure path.
    grep -A2 'macOS password for %u' "$INSTALL" | grep -q 'could not obtain admin access'
}

# ─── the apply hooks ──────────────────────────────────────────────────────────

@test "the apply's pre-auth prompt uses the same wording as install.sh" {
    grep -q 'macOS password for %u' "$HOOK"
    ! grep -q '\[chezmoi\] sudo password' "$HOOK"
}

@test "the pre-auth prompt explains the invisible typing too" {
    grep -q 'Nothing appears as you type' "$HOOK"
}

@test "macos-defaults gives a reason before asking a second time" {
    grep -q 'the earlier admin session expired' "$MACOS"
    ! grep -q '\[macos-defaults\] sudo password' "$MACOS"
}

@test "the second-ask explanation only prints when the ticket really lapsed" {
    # `sudo -v` is silent on a warm cache, so an unconditional message would be
    # announcing a prompt that never appears.
    run bash -c "grep -A6 'if ! sudo -n true' '$MACOS' | grep -c 'earlier admin session expired'"
    [ "$output" = "1" ]
}

# ─── the brew-bundle step ─────────────────────────────────────────────────────
# The worst prompt in the whole install: a cask running an Apple installer under
# sudo writes to /dev/tty, which the progress bar's 1Hz redraw erased. Ask for
# the password *before* the bar exists and the prompt never has to happen there.

@test "admin access is obtained before the progress bar starts" {
    # Order matters more than the call itself: the pre-flight is only a fix if
    # it runs while the screen is still clean.
    preflight="$(grep -n 'sudo -v -p' "$BREW" | head -n1 | cut -d: -f1)"
    bar="$(grep -n 'ui_progress_start' "$BREW" | head -n1 | cut -d: -f1)"
    [ -n "$preflight" ]
    [ -n "$bar" ]
    [ "$preflight" -lt "$bar" ]
}

@test "the brew step only asks when the ticket has actually lapsed" {
    # run_before_00 normally has it cached already; an unconditional prompt here
    # would be a third ask for a password the apply promised to take once.
    run bash -c "grep -A12 'if ! sudo -n true' '$BREW' | grep -c 'sudo -v -p'"
    [ "$output" = "1" ]
}

@test "the brew step's ask explains itself and survives QUIET=1" {
    grep -q 'need admin access' "$BREW"
    # dim/info, never explain: QUIET=1 drops prose, and this is a password prompt.
    grep -q 'dim "Nothing appears as you type' "$BREW"
    grep -q 'info "some apps install with an Apple installer' "$BREW"
}

@test "the brew step confirms the password was accepted" {
    # A prompt that vanishes with no acknowledgement reads as a prompt that was
    # missed. Say it landed, and say it will not come back.
    grep -q 'ok "admin access granted' "$BREW"
    grep -q 'not be asked again' "$BREW"
}

@test "the ticket is kept warm for the length of the bundle" {
    # A 65-package run is well past sudo's 5-minute cache, so pre-authorising
    # without a keeper just moves the prompt to minute 12 — behind the bar.
    grep -q 'sudo_keep_warm' "$BREW"
}

@test "Homebrew's own sudo calls get a prompt that names who is asking" {
    # Homebrew invokes sudo with -E, so it inherits SUDO_PROMPT. Without it a
    # cask asks with a bare "Password:" in the middle of a wall of output.
    grep -q 'export SUDO_PROMPT' "$BREW"
    grep -q 'SUDO_PROMPT="  macOS password for %u' "$BREW"
}

@test "a declined password does not fail the whole apply" {
    # Everything that does not need admin access must still install.
    grep -q 'no admin access — apps that need an installer package will be skipped' "$BREW"
}

@test "an expired prompt is reported as a password problem, not a bad download" {
    grep -q 'brew_sudo_failed' "$BREW"
    grep -q 'admin password was not entered' "$BREW"
}

# ─── the keeper ───────────────────────────────────────────────────────────────

@test "a single failed refresh does not end the keeper" {
    STUB="$BATS_TEST_TMPDIR/stub"
    CALLS="$BATS_TEST_TMPDIR/calls"
    mkdir -p "$STUB"
    # Fails once, then succeeds. The old `|| exit` gave up permanently here.
    cat >"$STUB/sudo" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$CALLS"
n=\$(wc -l < "$CALLS" | tr -d ' ')
[ "\$n" -eq 1 ] && exit 1
exit 0
EOF
    chmod +x "$STUB/sudo"

    sleep 30 &
    watch_pid=$!
    PATH="$STUB:$PATH" bash -c "source '$SUDO_LIB'; sudo_keep_warm $watch_pid 0"

    for _ in $(seq 1 60); do
        [ "$(wc -l <"$CALLS" 2>/dev/null | tr -d ' ')" -ge 3 ] && break
        sleep 0.2
    done
    kill "$watch_pid" 2>/dev/null || true

    # Three calls means it kept going past the first failure.
    [ "$(wc -l <"$CALLS" | tr -d ' ')" -ge 3 ]
}

@test "a sustained run of failures does end the keeper" {
    STUB="$BATS_TEST_TMPDIR/stub"
    CALLS="$BATS_TEST_TMPDIR/calls2"
    mkdir -p "$STUB"
    printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nexit 1\n' "$CALLS" >"$STUB/sudo"
    chmod +x "$STUB/sudo"

    sleep 30 &
    watch_pid=$!
    PATH="$STUB:$PATH" SUDO_KEEP_WARM_MAX_MISSES=2 \
        bash -c "source '$SUDO_LIB'; sudo_keep_warm $watch_pid 0"

    for _ in $(seq 1 40); do
        [ -s "$CALLS" ] && sleep 1 && break
        sleep 0.2
    done
    kill "$watch_pid" 2>/dev/null || true

    # Stops at the miss limit instead of spinning for the watched process's life.
    [ "$(wc -l <"$CALLS" | tr -d ' ')" -le 4 ]
}

@test "the refresh deadline is wall-clock, not a loop counter" {
    # The countdown form decremented by 2 per `sleep 2` iteration and refreshed
    # after 120 of them. An iteration also forks `kill -0`, so under the I/O load
    # of a 65-package brew bundle it costs more than 2s — at a 2.5s average the
    # "240s" refresh fired at 300s, exactly when the ticket had already expired.
    grep -q 'now="$(date +%s' "$SUDO_LIB"
    grep -q 'next=$((now + refresh_secs))' "$SUDO_LIB"
    # No decrementing counter left behind.
    ! grep -q 'refresh_in=$((refresh_in - 2))' "$SUDO_LIB"
}

@test "the default refresh leaves real margin inside sudo's 5-minute cache" {
    # 120s, not 240s: a no-op `sudo -n true` every two minutes costs nothing, and
    # the margin covers a machine that sleeps or stalls.
    grep -q 'refresh_secs="${2:-120}"' "$SUDO_LIB"
}

@test "refreshes keep firing on schedule even when each poll is slow" {
    # Drives the real keeper with a deliberately slow `sudo` stub. With a
    # wall-clock deadline the refresh count tracks elapsed time; with the old
    # counter it would lag behind by however long each iteration overran.
    STUB="$BATS_TEST_TMPDIR/stub"
    CALLS="$BATS_TEST_TMPDIR/calls3"
    mkdir -p "$STUB"
    printf '#!/usr/bin/env bash
sleep 1
echo "$*" >> "%s"
exit 0
' "$CALLS" >"$STUB/sudo"
    chmod +x "$STUB/sudo"

    sleep 30 &
    watch_pid=$!
    # refresh every 2s of wall clock, while each call itself burns 1s
    PATH="$STUB:$PATH" bash -c "source '$SUDO_LIB'; sudo_keep_warm $watch_pid 2"
    sleep 9
    kill "$watch_pid" 2>/dev/null || true

    # ~9s at a 2s cadence is 4-5 refreshes; assert a floor well clear of noise.
    [ "$(wc -l <"$CALLS" | tr -d ' ')" -ge 3 ]
}

@test "the miss limit is configurable and defaults to something small" {
    grep -q 'SUDO_KEEP_WARM_MAX_MISSES' "$SUDO_LIB"
    grep -q 'max_misses="${SUDO_KEEP_WARM_MAX_MISSES:-3}"' "$SUDO_LIB"
}
