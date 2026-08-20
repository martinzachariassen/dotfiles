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
}
teardown() { rm -rf "$FIX"; }

# Glyphs depend on the locale, so pin it — same convention as tests/log-lib.bats.
# Without this these tests assert Unicode while ui_init_glyphs may correctly pick
# the ASCII fallback, and they pass or fail on the runner's environment.
lib() { printf 'export LC_ALL=en_US.UTF-8; . "%s"; . "%s"; ui_init_logging;' "$LOG" "$BP"; }

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

@test "the bar parks when Homebrew goes silent, so a password prompt survives" {
    # A cask writes its sudo prompt straight to /dev/tty; the 1Hz redraw used to
    # erase it. After BREW_PROGRESS_STALL silent seconds the bar must clear
    # itself, say why, and stop repainting.
    run bash -c "$(lib) export BREW_PROGRESS_STALL=2; ui_progress_start 2 p >/dev/null
        { printf 'Installing docker-desktop\n'; sleep 4; printf 'SENT\n'; } |
            brew_progress_consume SENT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no output from Homebrew"* ]]
    [[ "$output" == *"docker-desktop"* ]]
    [[ "$output" == *"waiting for a password prompt"* ]]
}

@test "the stall note never claims a password is being asked for" {
    # It cannot know: a large download is silent for the same reason. Naming
    # both possibilities is the honest form.
    run bash -c "$(lib) brew_stall_note 'docker-desktop' 90"
    [[ "$output" == *"long download"* ]]
    [[ "$output" == *"or waiting for a password"* ]]
}

@test "parking happens once, not on every idle second" {
    run bash -c "$(lib) export BREW_PROGRESS_STALL=2; ui_progress_start 1 p >/dev/null
        { printf 'Installing x\n'; sleep 5; printf 'SENT\n'; } |
            brew_progress_consume SENT"
    count="$(printf '%s' "$output" | grep -c 'no output from Homebrew' || true)"
    [ "$count" = "1" ]
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
