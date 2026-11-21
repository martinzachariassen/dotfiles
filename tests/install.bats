#!/usr/bin/env bats

load helper

setup() {
  setup_sandbox

  BIN="$DOT_TMP/stub"
  TRIPPED="$DOT_TMP/tripped"
  mkdir -p "$BIN"

  local cmd
  for cmd in xcode-select brew git curl sudo sleep; do
    printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >>"%s"\nexit 1\n' \
      "$cmd" "$TRIPPED" >"$BIN/$cmd"
    chmod +x "$BIN/$cmd"
  done

  printf '#!/bin/sh\ncase ${1:-} in -s) echo "${STUB_OS:-Darwin}";; -m) echo "${STUB_ARCH:-arm64}";; esac\n' \
    >"$BIN/uname"
  printf '#!/bin/sh\necho "${STUB_UID:-501}"\n' >"$BIN/id"
  chmod +x "$BIN/uname" "$BIN/id"
}

teardown() { teardown_sandbox; }

bootstrap() {
  run env -i PATH="$BIN" HOME="$HOME" \
    DOTFILES_DIR="$DOT_TMP/checkout" \
    "$@" "$BASH" "$DOT_ROOT/install.sh"
}

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
  bootstrap
  [ -f "$TRIPPED" ]
  [[ $(cat "$TRIPPED") == xcode-select* ]]
  [[ $output != *"only"* ]]
}

stub_sleep() {
  printf '#!/bin/sh\nexec /bin/sleep "${STUB_SLEEP:-0}"\n' >"$BIN/sleep"
  chmod +x "$BIN/sleep"
}

stub_clt_present() {
  printf '#!/bin/sh\nexit 0\n' >"$BIN/xcode-select"
  chmod +x "$BIN/xcode-select"
}

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

stub_cold_homebrew() {
  BREW_PREFIX="$DOT_TMP/nobrew"
  KEEPALIVE="$DOT_TMP/keepalive"
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
  mkdir -p "$DOT_TMP/nobrew"

  bootstrap DOTFILES_BREW_PREFIX="$DOT_TMP/nobrew"
  [[ $(cat "$TRIPPED") == *"xcode-select --install"* ]]
  [[ $output == *"click Install in the dialog"* ]]
  [ "$(cat "$DOT_TMP/clt")" -gt 3 ]
  [[ $output == *"[2/5]"* ]]
}

@test "cold: Command Line Tools that never arrive time out, and stop the run" {
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
  [[ $output == *"installer NONINTERACTIVE=1"* ]]
  [[ $output == *"shell=/bin/bash"* ]]
}

@test "cold: the sudo keep-alive does not outlive the run" {
  stub_clt_present
  stub_cold_homebrew
  stub_sleep

  bootstrap_to_file DOTFILES_BREW_PREFIX="$BREW_PREFIX" STUB_SLEEP=0.05

  /bin/sleep 4

  local n
  n=$(cat "$KEEPALIVE" 2>/dev/null || echo 0)
  [ "$n" -gt 0 ] || {
    echo 'the keep-alive never ran; this test would prove nothing'
    return 1
  }
  [ "$n" -lt "$KEEPALIVE_MAX" ] || {
    echo "the keep-alive ran to the wall ($n calls): install.sh never killed it"
    return 1
  }
}
