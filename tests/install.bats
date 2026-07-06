#!/usr/bin/env bats
# Behavioural tests for install.sh — the one-shot `curl | bash` bootstrap for a
# fresh Mac (Xcode CLT → Homebrew → chezmoi → clone → hand off to the wizard).
#
# Why this exists:
#   This is the very first code a new machine runs, and it's the hardest to test
#   for real (it wants to install Homebrew and reboot into a GUI dialog). The
#   parts that actually break are the GUARDS and the HAND-OFF: refusing a non-Mac
#   or a root invocation, warning-but-continuing on non-Apple-Silicon, not
#   re-cloning an existing repo, and choosing the plain-text wizard vs. a direct
#   `chezmoi init` based on whether extra args were passed. We drive the REAL
#   script with every prerequisite stubbed (uname/id/xcode-select/brew/chezmoi/
#   git) and a fake, already-cloned source dir, so each situation is exercised
#   without touching the network or the system.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    INSTALL="$REPO_ROOT/install.sh"
    command -v bash >/dev/null 2>&1 || skip "bash not installed"

    # A fake, already-present source repo so the clone step is a no-op. Its
    # wizard.sh is what install.sh execs on the no-args path — a real (tiny)
    # script that just announces itself and its args.
    REPO="$(mktemp -d)"
    mkdir -p "$REPO/.git" "$REPO/scripts/bin"
    cat >"$REPO/scripts/bin/wizard.sh" <<'EOF'
#!/usr/bin/env bash
echo "WIZARD RAN args=[$*]"
EOF
    chmod +x "$REPO/scripts/bin/wizard.sh"

    STUBS="$(mktemp -d)"
    GIT_LOG="$STUBS/git.log"
    CHEZMOI_LOG="$STUBS/chezmoi.log"

    # uname: OS + arch come from env so a test can flip either axis. Defaults
    # describe the supported machine (Apple-Silicon macOS).
    cat >"$STUBS/uname" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -s) echo "${UNAME_S:-Darwin}" ;;
    -m) echo "${UNAME_M:-arm64}" ;;
    *)  echo "Darwin" ;;
esac
EOF
    # id -u: non-root by default; FAKE_UID=0 exercises the sudo guard.
    cat >"$STUBS/id" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -u ] && { echo "${FAKE_UID:-501}"; exit 0; }
exit 0
EOF
    # xcode-select: CLT already present (-p succeeds); --install is a no-op.
    cat >"$STUBS/xcode-select" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -p ] && exit 0
exit 0
EOF
    # brew present ⇒ load_brew short-circuits and the Homebrew install is skipped.
    cat >"$STUBS/brew" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    # chezmoi present ⇒ the brew-install-chezmoi step is skipped. On the args
    # path install.sh execs `chezmoi init …`; record it so we can assert on it.
    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
if [ "\$1" = --version ]; then echo "chezmoi version v2.0.0"; exit 0; fi
if [ "\$1" = init ]; then
    shift
    printf 'init %s\n' "\$*" >>"$CHEZMOI_LOG"
    echo "CHEZMOI INIT args=[\$*]"
    exit 0
fi
exit 0
EOF
    # git: record every call so we can prove clone is/ isn't invoked.
    cat >"$STUBS/git" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$GIT_LOG"
exit 0
EOF
    # sudo/curl exist only so the (skipped) Homebrew branch can't accidentally
    # hit the real binaries; they should never be called on these paths.
    printf '#!/usr/bin/env bash\nexit 0\n' >"$STUBS/sudo"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$STUBS/curl"
    chmod +x "$STUBS"/*
}

teardown() {
    [ -n "${REPO:-}" ] && rm -rf "$REPO"
    [ -n "${STUBS:-}" ] && rm -rf "$STUBS"
}

# ─── Happy path: no args ⇒ plain-text wizard ────────────────────────────────

@test "install hands off to the plain-text wizard when given no args" {
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" \
        GIT_LOG="$GIT_LOG" CHEZMOI_LOG="$CHEZMOI_LOG" bash "$INSTALL"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting the setup wizard"* ]]
    [[ "$output" == *"WIZARD RAN"* ]]
    # No args ⇒ it must NOT go straight to chezmoi init.
    [ ! -s "$CHEZMOI_LOG" ]
}

# ─── Advanced path: extra args ⇒ straight to chezmoi init ───────────────────

@test "install forwards extra args directly to chezmoi init (skips the wizard)" {
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" \
        GIT_LOG="$GIT_LOG" CHEZMOI_LOG="$CHEZMOI_LOG" bash "$INSTALL" --promptDefaults
    [ "$status" -eq 0 ]
    [[ "$output" == *"handing off directly to chezmoi init"* ]]
    [[ "$output" == *"CHEZMOI INIT"* ]]
    [[ "$output" != *"WIZARD RAN"* ]]
    grep -q -- '--apply' "$CHEZMOI_LOG"
    grep -q -- '--promptDefaults' "$CHEZMOI_LOG"
}

# ─── Guards ─────────────────────────────────────────────────────────────────

@test "install refuses to run on a non-macOS host" {
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" UNAME_S=Linux bash "$INSTALL"
    [ "$status" -ne 0 ]
    [[ "$output" == *"only supports macOS"* ]]
}

@test "install refuses to run as root" {
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" FAKE_UID=0 bash "$INSTALL"
    [ "$status" -ne 0 ]
    [[ "$output" == *"normal user"* ]]
}

@test "install warns but continues on non-Apple-Silicon" {
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" \
        GIT_LOG="$GIT_LOG" CHEZMOI_LOG="$CHEZMOI_LOG" UNAME_M=x86_64 bash "$INSTALL"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Apple Silicon"* ]]
    [[ "$output" == *"WIZARD RAN"* ]]  # warned, then proceeded
}

# ─── Idempotent clone ───────────────────────────────────────────────────────

@test "install does not re-clone when the repo is already present" {
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" \
        GIT_LOG="$GIT_LOG" CHEZMOI_LOG="$CHEZMOI_LOG" bash "$INSTALL"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Repo already present"* ]]
    [ ! -f "$GIT_LOG" ] || ! grep -q 'clone' "$GIT_LOG"
}

@test "install clones the repo when it is missing" {
    rm -rf "$REPO/.git"
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" \
        GIT_LOG="$GIT_LOG" CHEZMOI_LOG="$CHEZMOI_LOG" bash "$INSTALL"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cloning"* ]]
    grep -q 'clone' "$GIT_LOG"
}

# ─── Xcode Command Line Tools install ───────────────────────────────────────

@test "install triggers the Xcode CLT install when the tools are absent" {
    # `-p` fails until `--install` runs (which drops a marker that makes the next
    # `-p` succeed), so the bounded wait loop breaks on its very first poll — the
    # test exercises the install branch without ever hitting a real `sleep 5`.
    cat >"$STUBS/xcode-select" <<EOF
#!/usr/bin/env bash
marker="$STUBS/xcode.installed"
[ "\$1" = --install ] && { : >"\$marker"; exit 0; }
[ "\$1" = -p ] && { [ -f "\$marker" ] && exit 0 || exit 1; }
exit 0
EOF
    chmod +x "$STUBS/xcode-select"
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" \
        GIT_LOG="$GIT_LOG" CHEZMOI_LOG="$CHEZMOI_LOG" bash "$INSTALL"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installing Xcode Command Line Tools"* ]]
    [[ "$output" == *"Xcode Command Line Tools present"* ]]
    [[ "$output" == *"WIZARD RAN"* ]]
    [ -f "$STUBS/xcode.installed" ]  # --install was actually invoked
}
