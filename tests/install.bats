#!/usr/bin/env bats
#
# install.sh: the three guards, and nothing past them. PATH is the stub
# directory alone; every later command is a tripwire that records and fails.

load helper

setup() {
  setup_sandbox

  BIN="$DOT_TMP/stub"
  TRIPPED="$DOT_TMP/tripped"
  mkdir -p "$BIN"

  # #!/bin/sh, not env bash: there is no bash on the stub-only PATH, and a
  # stub that cannot start makes `uname` print nothing, which fails the macOS
  # guard and passes its test without either stub working.
  local cmd
  for cmd in xcode-select brew git curl sudo sleep; do
    printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >>"%s"\nexit 1\n' \
      "$cmd" "$TRIPPED" >"$BIN/$cmd"
    chmod +x "$BIN/$cmd"
  done

  # Each defaults to a machine that WOULD pass, so a test overrides one thing.
  printf '#!/bin/sh\ncase ${1:-} in -s) echo "${STUB_OS:-Darwin}";; -m) echo "${STUB_ARCH:-arm64}";; esac\n' \
    >"$BIN/uname"
  printf '#!/bin/sh\necho "${STUB_UID:-501}"\n' >"$BIN/id"
  chmod +x "$BIN/uname" "$BIN/id"
}

teardown() { teardown_sandbox; }

# `$BASH` by absolute path: there is no `bash` on the stub PATH.
bootstrap() {
  run env -i PATH="$BIN" HOME="$HOME" \
    DOTFILES_DIR="$DOT_TMP/checkout" \
    "$@" "$BASH" "$DOT_ROOT/install.sh"
}

# For the keep-alive test, which is the only one that can leave a process
# behind. Two things keep a LEAK from hanging the suite instead of failing it,
# and the first version of that test had neither -- so it passed with the kill
# in install.sh deleted:
#
#   >file  -- `run` captures through a command substitution, which waits for
#             every descendant still holding the pipe.
#   3>&-   -- bats reports on fd 3, and a background process inherits it. This
#             is bats' own documented rule for background tasks; without it the
#             orphan holds the formatter open and nothing ever finishes.
bootstrap_to_file() {
  BOOT_LOG="$DOT_TMP/install.out"
  env -i PATH="$BIN" HOME="$HOME" \
    DOTFILES_DIR="$DOT_TMP/checkout" \
    "$@" "$BASH" "$DOT_ROOT/install.sh" >"$BOOT_LOG" 2>&1 3>&- || true
}

assert_went_no_further() {
  [ "$status" -ne 0 ]
  [ ! -f "$TRIPPED" ] || {
    echo "the guard did not stop the run; install.sh went on to call:"
    cat "$TRIPPED"
    return 1
  }
}

@test "guard: refuses a machine that is not macOS" {
  bootstrap STUB_OS=Linux
  [[ $output == *"macOS only"* ]]
  assert_went_no_further
}

@test "guard: refuses to run as root" {
  bootstrap STUB_UID=0
  [[ $output == *"as root"* ]]
  assert_went_no_further
}

@test "guard: refuses an Intel Mac, and says what it found" {
  bootstrap STUB_ARCH=x86_64
  [[ $output == *"Apple Silicon only"* ]]
  [[ $output == *"x86_64"* ]]
  assert_went_no_further
}

@test "guard: the guards pass on the machine this repo targets" {
  # Otherwise the tests above prove only that the script exits. Reaching
  # xcode-select means all three guards let the machine through.
  bootstrap
  [ -f "$TRIPPED" ]
  [[ $(cat "$TRIPPED") == xcode-select* ]]
  [[ $output != *"only"* ]]
}

# --- The cold machine -------------------------------------------------------
#
# Steps 1 and 2, the two the install-smoke workflow cannot reach: a hosted
# runner already has the Command Line Tools and Homebrew, so both take their
# "already installed" branch.
#
# What is under test is the part that is OURS -- the polling loop, its timeout,
# and the sudo keep-alive. Homebrew's own installer is stubbed out; it is the
# most-run shell script on macOS and not this repo's to verify.

# `sleep` costs nothing unless a test asks it to. The keep-alive tests do: a
# loop whose sleep returns instantly spins at full speed.
stub_sleep() {
  printf '#!/bin/sh\nexec /bin/sleep "${STUB_SLEEP:-0}"\n' >"$BIN/sleep"
  chmod +x "$BIN/sleep"
}

# The Command Line Tools are already there, which is what steps 2 and beyond
# need to be reachable at all.
stub_clt_present() {
  printf '#!/bin/sh\nexit 0\n' >"$BIN/xcode-select"
  chmod +x "$BIN/xcode-select"
}

# xcode-select: `-p` fails until it has been asked N times, then succeeds. The
# counter is a file because every call is a new process.
#
# `read`, never `cat`: PATH is the stub directory alone, so the only commands
# a stub can use are shell builtins. A `cat` here silently failed on every
# call, `|| echo 0` swallowed it, and the counter never left 1.
stub_clt_appears_after() {
  cat >"$BIN/xcode-select" <<EOF
#!/bin/sh
if [ "\${1:-}" = "--install" ]; then
  printf 'xcode-select --install\n' >>"$TRIPPED"
  exit 0
fi
n=0
[ -f "$DOT_TMP/clt" ] && read n <"$DOT_TMP/clt"
n=\$((n + 1))
printf '%s\n' "\$n" >"$DOT_TMP/clt"
[ "\$n" -gt $1 ] && exit 0
exit 1
EOF
  chmod +x "$BIN/xcode-select"
}

# A machine with no Homebrew: the prefix is an empty directory, so step 2 takes
# the branch that installs it.
#
# The keep-alive loop must always END, and how far it got is the verdict.
#
# Left running, a leak does not fail the suite -- it HANGS it: install.sh never
# exits while its background child lives, and bats waits on install.sh. A hang
# reports nothing, so an unkilled loop would look like an unfinished run rather
# than a bug. So `sudo -n` refuses after KEEPALIVE_MAX calls, and the loop ends
# either way. Killed, it stops far short; left alone, it runs to the wall.
stub_cold_homebrew() {
  BREW_PREFIX="$DOT_TMP/nobrew"
  KEEPALIVE="$DOT_TMP/keepalive"
  # Three seconds of free running at STUB_SLEEP=0.05, against the ten or so
  # iterations a killed loop manages inside the installer's half second. The
  # gap is what makes the verdict a threshold rather than a race.
  KEEPALIVE_MAX=60
  mkdir -p "$BREW_PREFIX"

  cat >"$BIN/sudo" <<EOF
#!/bin/sh
case "\${1:-}" in
  -v) printf 'sudo -v\n' >>"$TRIPPED"; exit 0 ;;
  -n)
    n=0
    [ -f "$KEEPALIVE" ] && read n <"$KEEPALIVE"
    n=\$((n + 1))
    printf '%s\n' "\$n" >"$KEEPALIVE"
    [ "\$n" -ge $KEEPALIVE_MAX ] && exit 1
    exit 0
    ;;
esac
exit 0
EOF

  # What `NONINTERACTIVE=1 /bin/bash -c "$(curl ...)"` will be handed. It reports
  # the two things install.sh promises Homebrew's installer, and nothing else:
  # builtins only, because PATH is the stub directory and `env` is not on it.
  # /bin/sleep by absolute path, not the stub: this one has to take real time,
  # so the keep-alive is demonstrably running when the kill arrives. Through
  # the stub it would shrink along with the keep-alive's own sleep and the
  # loop could be killed before it ever ran once.
  cat >"$BIN/curl" <<'EOF'
#!/bin/sh
printf '%s\n' \
  'printf "installer NONINTERACTIVE=%s shell=%s\n" "$NONINTERACTIVE" "$BASH"' \
  '/bin/sleep 0.5'
EOF
  chmod +x "$BIN/sudo" "$BIN/curl"
}

@test "cold: no Command Line Tools -- it triggers the installer, then waits" {
  stub_clt_appears_after 3
  stub_sleep
  # An empty prefix, so step 2 takes its cold branch and stops on the `sudo`
  # tripwire. Without it the run reaches the REAL Homebrew on this machine and
  # what happens next is the machine's business, not the test's.
  mkdir -p "$DOT_TMP/nobrew"

  bootstrap DOTFILES_BREW_PREFIX="$DOT_TMP/nobrew"
  [[ $(cat "$TRIPPED") == *"xcode-select --install"* ]]
  [[ $output == *"click Install in the dialog"* ]]
  # It polled rather than giving up, and it got past step 1.
  [ "$(cat "$DOT_TMP/clt")" -gt 3 ]
  [[ $output == *"[2/5]"* ]]
}

@test "cold: Command Line Tools that never arrive time out, and stop the run" {
  # 180 attempts is thirty minutes of real waiting; the point is that the loop
  # is bounded at all, and that it does not fall through to Homebrew.
  stub_clt_appears_after 100000
  stub_sleep

  bootstrap
  [ "$status" -ne 0 ]
  [[ $output == *"Timed out waiting for Command Line Tools"* ]]
  [[ $output == *"re-run this script"* ]]
  [[ $output != *"[2/5]"* ]]
  [[ $(cat "$TRIPPED") != *"sudo"* ]]
}

@test "cold: no Homebrew -- sudo is primed and the installer gets what it needs" {
  stub_clt_present
  stub_cold_homebrew
  stub_sleep

  bootstrap DOTFILES_BREW_PREFIX="$BREW_PREFIX" STUB_SLEEP=0.2

  [[ $(cat "$TRIPPED") == *"sudo -v"* ]]
  # NONINTERACTIVE, because a bootstrap has nobody to answer prompts, and
  # /bin/bash, because bash 5 is not installed until the step after this one.
  [[ $output == *"installer NONINTERACTIVE=1"* ]]
  [[ $output == *"shell=/bin/bash"* ]]
}

@test "cold: the sudo keep-alive does not outlive the run" {
  # `exec` runs no EXIT trap, so the loop is killed explicitly before the
  # handoff. Leaked, it would sit refreshing your sudo credential forever, and
  # nothing on the machine would ever mention it.
  stub_clt_present
  stub_cold_homebrew
  stub_sleep

  bootstrap_to_file DOTFILES_BREW_PREFIX="$BREW_PREFIX" STUB_SLEEP=0.05

  # Long enough for a loop nobody killed to reach the wall on its own.
  /bin/sleep 4

  local n
  n=$(cat "$KEEPALIVE" 2>/dev/null || echo 0)
  # It has to have run at all, or a keep-alive that never started would pass.
  [ "$n" -gt 0 ] || {
    echo 'the keep-alive never ran; this test would prove nothing'
    return 1
  }
  [ "$n" -lt "$KEEPALIVE_MAX" ] || {
    echo "the keep-alive ran to the wall ($n calls): install.sh never killed it"
    return 1
  }
}
