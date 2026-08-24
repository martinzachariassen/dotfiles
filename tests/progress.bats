#!/usr/bin/env bats
# Progress reporting must be driven by real data, never decoration.
#
# The denominator comes from Homebrew's own contract: bundle/installer.rb prints
# exactly one line per Brewfile entry — "Using <name>", or "<verb> <name>" for
# Installing/Upgrading/Tapping. These tests pin that parsing, the counter, and
# the two platform traps that made earlier versions wrong on a real Mac.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LOG="$REPO_ROOT/scripts/lib/log.sh"
    BP="$REPO_ROOT/scripts/lib/brew-progress.sh"
    FIX="$(mktemp -d)"
    # The consumer asks `sudo -n true` whether a password prompt is possible.
    # Left alone, the answer depends on whether the developer running the suite
    # happened to use sudo in the last five minutes — so it is off by default
    # here, and the tests that care pin it with sudo_stub.
    export BREW_PROGRESS_SUDO_PROBE=0
}
teardown() { rm -rf "$FIX"; }

# Glyphs depend on the locale, so pin it — same convention as tests/log-lib.bats.
# Without this these tests assert Unicode while ui_init_glyphs may correctly pick
# the ASCII fallback, and they pass or fail on the runner's environment.
lib() { printf 'export LC_ALL=en_US.UTF-8; . "%s"; . "%s"; ui_init_logging;' "$LOG" "$BP"; }

# sudo_stub EXIT — put a `sudo` on PATH that always exits EXIT, and re-enable
# the probe. 0 = ticket held (nothing can prompt), 1 = ticket missing.
sudo_stub() {
    mkdir -p "$FIX/bin"
    printf '#!/usr/bin/env bash\nexit %s\n' "$1" >"$FIX/bin/sudo"
    chmod +x "$FIX/bin/sudo"
    printf 'export PATH="%s:$PATH" BREW_PROGRESS_SUDO_PROBE=1;' "$FIX/bin"
}

# has / lacks NEEDLE HAYSTACK — substring assertions that actually fail the test.
#
# bats' errexit does not fire on a bare `[[ … ]]`, so an inline pattern check
# that is not the last line of a test is silently ignored — every assertion
# above the final one passes for free. A function returning non-zero does abort,
# so these give the assertion back its teeth.
has() {
    case "$2" in
        *"$1"*) ;;
        *)
            printf 'expected to find: %s\n---\n%s\n---\n' "$1" "$2" >&2
            return 1
            ;;
    esac
}
lacks() {
    case "$2" in
        *"$1"*)
            printf 'expected NOT to find: %s\n---\n%s\n---\n' "$1" "$2" >&2
            return 1
            ;;
        *) ;;
    esac
}

# sudo_stub_after N — a `sudo` that fails its first N-1 calls then succeeds,
# standing in for a password being typed partway through the run.
sudo_stub_after() {
    mkdir -p "$FIX/bin"
    cat >"$FIX/bin/sudo" <<EOF
#!/usr/bin/env bash
n=\$(cat "$FIX/calls" 2>/dev/null || echo 0)
n=\$((n + 1))
printf '%s' "\$n" >"$FIX/calls"
[ "\$n" -ge $1 ]
EOF
    chmod +x "$FIX/bin/sudo"
    printf 'export PATH="%s:$PATH" BREW_PROGRESS_SUDO_PROBE=1;' "$FIX/bin"
}

# ─── the bar itself ───────────────────────────────────────────────────────────

@test "the bar fills in proportion to real progress" {
    run bash -c "$(lib) UI_PROGRESS_WIDTH=10; _ui_bar 0 10"
    [ "$output" = "░░░░░░░░░░" ]
    run bash -c "$(lib) UI_PROGRESS_WIDTH=10; _ui_bar 5 10"
    [ "$output" = "█████░░░░░" ]
    run bash -c "$(lib) UI_PROGRESS_WIDTH=10; _ui_bar 10 10"
    [ "$output" = "██████████" ]
}

@test "the bar never overflows or slices a multi-byte glyph" {
    # Built by appending, not by substring: bash substring arithmetic is
    # byte-based and would cut a 3-byte block character in thirds.
    run bash -c "$(lib) UI_PROGRESS_WIDTH=8; _ui_bar 99 8"
    [ "$output" = "████████" ]
    run bash -c "$(lib) UI_PROGRESS_WIDTH=8; _ui_bar 0 0"
    [ -n "$output" ]
}

@test "the bar has an ASCII fallback for non-UTF-8 terminals" {
    # Locale must be set before ui_init_logging, which re-runs ui_init_glyphs.
    run bash -c "export LC_ALL=C LANG=C LC_CTYPE=C; . '$LOG'; ui_init_logging; UI_PROGRESS_WIDTH=4; _ui_bar 2 4"
    [ "$output" = "##--" ]
}

@test "the counter survives the pipeline subshell" {
    # ui_progress_* keeps state in a file precisely because the consumer runs as
    # `cmd | while read`, whose body bash executes in a subshell.
    run bash -c "$(lib) ui_progress_start 3 x >/dev/null
        printf 'a\nb\n' | while read -r l; do ui_progress_tick \"\$l\" >/dev/null; done
        printf '%s' \"\$(ui_progress_count)\""
    [ "$output" = "2" ]
}

# ─── brew_pkg_count — the denominator ─────────────────────────────────────────

@test "counting entries yields exactly one number" {
    printf 'brew "jq"\ncask "vlc"\nmas "X", id: 1\ntap "a/b"\n' >"$FIX/Brewfile"
    run bash -c ". '$BP'; brew_pkg_count '$FIX/Brewfile'"
    [ "$output" = "4" ]
}

@test "a Brewfile with no entries counts 0 without breaking arithmetic" {
    # Regression: `grep -c` prints "0" AND exits 1, so a `|| echo 0` fallback
    # emitted the count twice, turning $((total + $(...))) into a syntax error.
    # This is not hypothetical — packages/Brewfile.personal is comment-only.
    printf '# just a comment\n#\n' >"$FIX/Brewfile"
    run bash -c ". '$BP'; brew_pkg_count '$FIX/Brewfile'"
    [ "$output" = "0" ]
    run bash -c ". '$BP'; total=0; total=\$((total + \$(brew_pkg_count '$FIX/Brewfile'))); echo \$total"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "a missing Brewfile counts 0 rather than erroring" {
    run bash -c ". '$BP'; total=0; total=\$((total + \$(brew_pkg_count '$FIX/nope'))); echo \$total"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "the repo's own Brewfiles all count cleanly" {
    for f in "$REPO_ROOT"/packages/Brewfile*; do
        case "$f" in *cspell* | *vscode*) continue ;; esac
        run bash -c ". '$BP'; brew_pkg_count '$f'"
        [ "$status" -eq 0 ]
        [[ "$output" =~ ^[0-9]+$ ]]
    done
}

# ─── line parsing ─────────────────────────────────────────────────────────────

@test "entry names are extracted for every verb Homebrew uses" {
    # Verbs confirmed from bundle/{brew,cask,tap}.rb: Installing/Upgrading/Tapping.
    run bash -c ". '$BP'; brew_entry_name 'Using jq'"
    [ "$output" = "jq" ]
    run bash -c ". '$BP'; brew_entry_name 'Installing ripgrep'"
    [ "$output" = "ripgrep" ]
    run bash -c ". '$BP'; brew_entry_name 'Upgrading bat'"
    [ "$output" = "bat" ]
    run bash -c ". '$BP'; brew_entry_name 'Tapping hashicorp/tap'"
    [ "$output" = "hashicorp/tap" ]
}

@test "entry names survive ANSI colour codes" {
    # Regression: the first version used `\|` alternation, a GNU sed extension.
    # macOS ships BSD sed, which matched a literal pipe, so every name came back
    # as the checkmark or the verb.
    run bash -c ". '$BP'; brew_entry_name \"\$(printf '\033[32m✔︎\033[0m Installing ripgrep')\""
    [ "$output" = "ripgrep" ]
    run bash -c ". '$BP'; brew_entry_name 'Installing microsoft-office cask. It is not currently installed.'"
    [ "$output" = "microsoft-office" ]
}

@test "download labels never present a URL fragment as a package name" {
    run bash -c ". '$BP'; brew_fetch_label '==> Fetching ripgrep'"
    [ "$output" = "fetching ripgrep" ]
    run bash -c ". '$BP'; brew_fetch_label '==> Downloading https://ghcr.io/v2/homebrew/core/jq/manifests/1.7.1'"
    [ "$output" = "downloading" ]
}

# ─── the consumer ─────────────────────────────────────────────────────────────

@test "one tick per entry, and noise is ignored" {
    run bash -c "$(lib) ui_progress_start 5 p >/dev/null
        { printf '==> Downloading Homebrew API data\n'
          printf 'Using jq\n'
          printf 'Using fd\n'
          printf '==> Fetching ripgrep\n'
          printf 'Installing ripgrep\n'
          printf 'Tapping hashicorp/tap\n'
          printf 'Upgrading bat\n'
          printf '\`brew bundle\` complete! 5 Brewfile dependencies now installed.\n'
          printf 'SENT\n'; } | brew_progress_consume SENT >/dev/null
        printf '%s' \"\$(ui_progress_count)\""
    # 5 entries; the Downloading/Fetching/complete lines must not count.
    [ "$output" = "5" ]
}

@test "Homebrew's own dependency narration never ticks the counter" {
    # The 101% bug: "==> Installing <formula> dependency: <dep>" uses the same
    # verb as bundle's own per-entry lines, so a substring match counted every
    # transitive dependency and overshot the real denominator.
    run bash -c "$(lib) ui_progress_start 2 p >/dev/null
        { printf 'Installing xcodes\n'
          printf '==> Installing dependencies for xcodes: openssl@3, ruby\n'
          printf '==> Installing xcodes dependency: openssl@3\n'
          printf '==> Installing xcodes dependency: ruby\n'
          printf '==> Installing xcodes from xcodesorg/made\n'
          printf 'Using aria2\n'
          printf 'SENT\n'; } | brew_progress_consume SENT >/dev/null
        printf '%s' \"\$(ui_progress_count)\""
    [ "$output" = "2" ]
}

@test "a run of real Brewfile output lands exactly on the declared total" {
    # End-to-end shape of the failing install: declared entries plus Homebrew
    # chatter must finish at N/N, never N+1/N.
    run bash -c "$(lib) ui_progress_start 3 p >/dev/null
        { printf '==> Downloading https://ghcr.io/v2/homebrew/core/x\n'
          printf 'Installing stats\n'
          printf '==> Installing dependencies for stats: a\n'
          printf 'Installing obsidian\n'
          printf '==> Fetching intellij-idea\n'
          printf 'Installing intellij-idea\n'
          printf '\`brew bundle\` complete! 3 Brewfile dependencies now installed.\n'
          printf 'SENT\n'; } | brew_progress_consume SENT >/dev/null
        printf '%s' \"\$(ui_progress_count)\""
    [ "$output" = "3" ]
}

# ─── password prompts ─────────────────────────────────────────────────────────
# A cask's `sudo` prompt goes straight to /dev/tty — Homebrew hands the child a
# closed stdin, so sudo opens the terminal itself and the prompt never enters
# the pipe this consumer reads. The 1Hz `\r\033[K` redraw then erased it, which
# is what made a real install look frozen and "work sometimes". The consumer
# must therefore never draw while a prompt is possible, and it decides that by
# asking sudo rather than by guessing from silence.

@test "the bar never draws while the admin ticket is missing" {
    run bash -c "$(sudo_stub 1) $(lib) ui_progress_start 2 p >/dev/null
        { printf 'Installing docker-desktop\n'; sleep 3; printf 'SENT\n'; } |
            brew_progress_consume SENT"
    [ "$status" -eq 0 ]
    has "Administrator password needed" "$output"
    # Nothing that would overwrite the prompt: no bar, no per-item repaint.
    lacks "░" "$output"
    lacks "█" "$output"
}

@test "the banner says plainly that a password is being asked for" {
    # The old note could not know — a large download is silent for the same
    # reason — so it hedged. Asking sudo removes the ambiguity, and the wording
    # has to be unambiguous too: this is the one moment a human is needed.
    run bash -c "$(lib) brew_sudo_park 'docker-desktop'"
    has "Administrator password needed" "$output"
    has "docker-desktop" "$output"
    has "Nothing appears as you type" "$output"
    has "Touch ID" "$output"
    has "paused" "$output"
}

@test "the banner survives QUIET=1" {
    # explain() drops prose under QUIET; a password prompt must never be dropped.
    run bash -c "$(lib) QUIET=1 brew_sudo_park 'docker-desktop'"
    has "Administrator password needed" "$output"
    has "Nothing appears as you type" "$output"
}

@test "parking happens once, not on every poll" {
    run bash -c "$(sudo_stub 1) $(lib) export BREW_SUDO_POLL=1
        ui_progress_start 1 p >/dev/null
        { printf 'Installing x\n'; sleep 4; printf 'SENT\n'; } |
            brew_progress_consume SENT"
    count="$(printf '%s' "$output" | grep -c 'Administrator password needed' || true)"
    [ "$count" = "1" ]
}

@test "the bar keeps its clock running while the ticket is held" {
    # The old behaviour parked on silence alone, which froze the elapsed clock
    # for the several minutes a big cask download takes. A held ticket rules a
    # prompt out, so silence can be reported as what it is.
    run bash -c "$(sudo_stub 0) $(lib) export BREW_PROGRESS_STALL=2
        ui_progress_start 2 p >/dev/null
        { printf 'Installing docker-desktop\n'; sleep 4; printf 'SENT\n'; } |
            brew_progress_consume SENT"
    has "still downloading" "$output"
    lacks "Administrator password needed" "$output"
}

@test "the quiet label never claims a password is being asked for" {
    # It is only ever reached with the ticket held, where a prompt is impossible.
    run bash -c "$(lib) brew_quiet_label 'docker-desktop' 125"
    has "docker-desktop" "$output"
    has "2m05s" "$output"
    lacks "password" "$output"
    lacks "Password" "$output"
}

@test "Homebrew's own sudo announcement parks the bar on the spot" {
    # Homebrew prints exactly one line before it calls sudo. Waiting for the
    # poll interval instead would leave the bar repainting over the prompt for
    # up to BREW_SUDO_POLL seconds, which is how the prompt got erased.
    run bash -c "$(sudo_stub 1) $(lib) export BREW_SUDO_POLL=999
        ui_progress_start 2 p >/dev/null
        { printf 'Using jq\n'
          printf '==> Running installer for docker-desktop with \`sudo\` (which may request your password)...\n'
          sleep 2
          printf 'SENT\n'; } | brew_progress_consume SENT"
    has "Administrator password needed" "$output"
    has "docker-desktop" "$output"
}

@test "the announcement is recognised in every wording Homebrew has shipped" {
    run bash -c "$(lib)
        brew_is_sudo_notice '==> Running installer for x with \`sudo\` (which may request your password)...' && echo A
        brew_is_sudo_notice '==> Running installer for x; the password may be necessary.' && echo B
        brew_is_sudo_notice '==> Installing Cask docker-desktop' || echo C"
    has "A" "$output"
    has "B" "$output"
    has "C" "$output"
}

@test "the announcement names the cask, and falls back when the wording changes" {
    run bash -c "$(lib) brew_sudo_notice_target '==> Running installer for docker-desktop with \`sudo\`' ''"
    [ "$output" = "docker-desktop" ]
    run bash -c "$(lib) brew_sudo_notice_target '==> something new with \`sudo\`' 'obsidian'"
    [ "$output" = "obsidian" ]
}

@test "the bar comes back with a confirmation once the password is accepted" {
    # Silence after a prompt is answered is indistinguishable from silence
    # before it, so the run has to say which one happened.
    run bash -c "$(sudo_stub_after 3) $(lib) export BREW_SUDO_POLL=1
        ui_progress_start 2 p >/dev/null
        { printf 'Installing docker-desktop\n'; sleep 5; printf 'SENT\n'; } |
            brew_progress_consume SENT"
    has "Administrator password needed" "$output"
    has "password accepted" "$output"
}

@test "a prompt that was declined is not reported as accepted" {
    run bash -c "$(lib) $(sudo_stub 1) brew_sudo_unpark"
    has "without admin access" "$output"
    lacks "accepted" "$output"
}

@test "entries still count while the bar is parked" {
    # The counter has to survive the park, or the bar resumes at the wrong place
    # and the run reports fewer packages than it installed.
    run bash -c "$(sudo_stub 1) $(lib) ui_progress_start 3 p >/dev/null
        { printf 'Using jq\n'; printf 'Using fd\n'; printf 'Using bat\n'
          printf 'SENT\n'; } | brew_progress_consume SENT >/dev/null
        printf '%s' \"\$(ui_progress_count)\""
    [ "$output" = "3" ]
}

@test "a parked run still shows the packages it finishes" {
    # Past a declined prompt Homebrew keeps going. Nothing may repaint, but a
    # settled line per completed entry keeps the run from looking dead.
    run bash -c "$(sudo_stub 1) $(lib) ui_progress_start 2 p >/dev/null
        { printf 'Using jq\n'; printf 'Using fd\n'; printf 'SENT\n'; } |
            brew_progress_consume SENT"
    has "[1/2] jq" "$output"
    has "[2/2] fd" "$output"
}

@test "the probe never reads from the pipe it is polling beside" {
    # `sudo -n true` inheriting the consumer's stdin would swallow a line of
    # Homebrew's output, silently losing a tick.
    grep -q 'sudo -n true </dev/null' "$BP"
}

@test "a sudo timeout is reported as a password problem, not a bad download" {
    printf 'sudo: timed out reading password\nError: Failure while executing\n' >"$FIX/log"
    run bash -c "$(lib) brew_sudo_failed '$FIX/log' && echo YES"
    [ "$output" = "YES" ]
    # ...and the line itself survives into the error extract, which used to grep
    # only for error/fatal and so showed a dead download instead.
    run bash -c "$(lib) brew_error_lines '$FIX/log' 12"
    has "timed out reading password" "$output"
}

@test "an ordinary download failure is not blamed on the password" {
    printf 'Error: Download failed on Cask docker-desktop\n' >"$FIX/log"
    run bash -c "$(lib) brew_sudo_failed '$FIX/log' || echo NO"
    [ "$output" = "NO" ]
}

@test "the consumer stops at the sentinel instead of hanging" {
    # macOS bash 3.2 returns 1 from `read -t` for BOTH timeout and EOF, so the
    # loop cannot tell them apart — hence the sentinel. Without it this hangs.
    run bash -c "$(lib) ui_progress_start 1 p >/dev/null
        { printf 'Using jq\n'; printf 'SENT\n'; sleep 5; } | brew_progress_consume SENT >/dev/null
        echo RETURNED"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RETURNED"* ]]
}

@test "a producer killed mid-stream cannot hang the consumer forever" {
    run bash -c "$(lib) ui_progress_start 1 p >/dev/null
        BREW_PROGRESS_MAX_IDLE=1 
        export BREW_PROGRESS_MAX_IDLE
        { printf 'Using jq\n'; sleep 4; } | brew_progress_consume SENT >/dev/null
        echo RETURNED"
    [[ "$output" == *"RETURNED"* ]]
}

# ─── honesty ──────────────────────────────────────────────────────────────────

@test "work with no denominator gets a timer, not a fake bar" {
    # Apple's GUI installer exposes no progress data, so install.sh must not
    # draw a bar for it.
    grep -q "waiting for Apple" "$REPO_ROOT/install.sh"
    ! sed -n '/Xcode Command Line Tools/,/^# --- 2\./p' "$REPO_ROOT/install.sh" | grep -q 'bar '
}

@test "the brew hook derives its total from the Brewfiles, not a constant" {
    local hook="$REPO_ROOT/src/.chezmoiscripts/run_after_02-brew-bundle.sh.tmpl"
    grep -q 'brew_pkg_count' "$hook"
    grep -q 'ui_progress_start "$total"' "$hook"
    # The parsing lives in the lib, so it is testable and the hook stays thin.
    grep -q 'brew_progress_consume' "$hook"
}
