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
    SUDO_LIB="$REPO_ROOT/scripts/lib/sudo.sh"
    MACOS="$REPO_ROOT/scripts/bin/macos-defaults.sh"
    HOOK="$REPO_ROOT/src/.chezmoiscripts/run_before_00-sudo-cache.sh.tmpl"
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

@test "the miss limit is configurable and defaults to something small" {
    grep -q 'SUDO_KEEP_WARM_MAX_MISSES' "$SUDO_LIB"
    grep -q 'max_misses="${SUDO_KEEP_WARM_MAX_MISSES:-3}"' "$SUDO_LIB"
}
