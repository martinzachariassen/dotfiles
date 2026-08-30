#!/usr/bin/env bats
# Behavioural tests for `chezsetup`, which merges the old chezreset/chezreinit
# into one verb: default mode fills in newly-added setup keys (chezmoi init +
# chezapply, keeping existing answers); --reset/-r replays first-time setup
# (state reset + re-run the wizard, overriding saved answers). Extracts the
# real function body from the committed template and runs it under zsh
# against stubbed git/chezmoi/wizard.sh/chezapply/_chez_run.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"

    FAKE="$(mktemp -d)"
    mkdir -p "$FAKE/scripts/bin"

    STUBS="$(mktemp -d)"
    GIT_LOG="$STUBS/git.log"
    INIT_LOG="$STUBS/init.log"
    RESET_LOG="$STUBS/reset.log"
    APPLY_LOG="$STUBS/apply.log"
    RUN_LOG="$STUBS/run.log"
    WIZARD_LOG="$STUBS/wizard.log"
    : >"$GIT_LOG"
    : >"$INIT_LOG"
    : >"$RESET_LOG"
    : >"$APPLY_LOG"
    : >"$RUN_LOG"
    : >"$WIZARD_LOG"

    cat >"$FAKE/scripts/bin/wizard.sh" <<EOF
#!/usr/bin/env bash
printf 'wizard %s\n' "\$*" >>"$WIZARD_LOG"
EOF
    chmod +x "$FAKE/scripts/bin/wizard.sh"

    cat >"$STUBS/git" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$GIT_LOG"
exit \${GIT_RC:-0}
EOF
    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
if [ "\$1" = init ]; then
    shift
    printf 'init %s\n' "\$*" >>"$INIT_LOG"
    exit \${CHEZMOI_INIT_RC:-0}
fi
if [ "\$1" = state ] && [ "\$2" = reset ]; then
    shift 2
    printf 'state reset %s\n' "\$*" >>"$RESET_LOG"
    exit \${CHEZMOI_RESET_RC:-0}
fi
exit 0
EOF
    chmod +x "$STUBS/git" "$STUBS/chezmoi"
}

teardown() {
    [ -n "${FAKE:-}" ] && rm -rf "$FAKE"
    [ -n "${STUBS:-}" ] && rm -rf "$STUBS"
}

extract() {
    local fn
    for fn in "$@"; do
        sed -n "/^${fn}() {/,/^}/p" "$ZSHRC"
    done | sed "s|^    local src={{.*}}|    local src=\"$FAKE\"|"
}

have_tty() { { : </dev/tty; } >/dev/null 2>&1; }

# chezapply / _chez_run are chezsetup's collaborators — stub them so this file
# tests chezsetup's own branching, not theirs (already covered elsewhere).
# Built inside run_zsh (not at file scope) so it picks up this test's
# per-setup() log paths rather than whatever was in scope at file-load time.
run_zsh() {
    local stubfn="
chezapply() { printf \"chezapply %s\n\" \"\$*\" >>\"$APPLY_LOG\"; }
_chez_run() { printf \"_chez_run %s\n\" \"\$*\" >>\"$RUN_LOG\"; }
"
    run env PATH="$STUBS:$PATH" WIZARD_LOG="$WIZARD_LOG" \
        GIT_RC="${GIT_RC:-0}" CHEZMOI_INIT_RC="${CHEZMOI_INIT_RC:-0}" CHEZMOI_RESET_RC="${CHEZMOI_RESET_RC:-0}" \
        zsh -c "$stubfn
$1"
}

# ─── default mode: fill in new keys, never touch run-once state or the wizard ─

@test "chezsetup (default) pulls, fills in new keys via chezmoi init, then applies" {
    run_zsh "$(extract chezsetup); chezsetup"
    [ "$status" -eq 0 ]
    grep -q 'pull --ff-only' "$GIT_LOG"
    grep -q '^init ' "$INIT_LOG"
    grep -q '^chezapply ' "$APPLY_LOG"
    [ ! -s "$RESET_LOG" ]  # never resets state in default mode
    [ ! -s "$WIZARD_LOG" ] # never touches the wizard in default mode
    [[ "$output" == *"filling in any new/unanswered setup keys only"* ]] || return 1
    [[ "$output" == *"chezsetup --reset"* ]] || return 1
}

@test "chezsetup (default) aborts before chezmoi init if git pull fails" {
    GIT_RC=7 run_zsh "$(extract chezsetup); chezsetup"
    [ "$status" -eq 7 ]
    [ ! -s "$INIT_LOG" ]
    [ ! -s "$APPLY_LOG" ]
}

@test "chezsetup forwards unrecognized args to chezapply in default mode" {
    run_zsh "$(extract chezsetup); chezsetup -v"
    [ "$status" -eq 0 ]
    grep -q '^chezapply -v' "$APPLY_LOG"
}

# ─── --reset/-r: replay first-time setup ────────────────────────────────────
# The confirm prompt reads from /dev/tty directly (no gum branch), which a
# bats subprocess can't script input into — so these tests exercise the
# `[ -r /dev/tty ]` false branch (skips the prompt, proceeds unattended),
# matching how a CI/non-interactive run actually behaves. They skip on a
# real controlling tty rather than hang; see chezmirror.bats for the same pattern.

@test "chezsetup --reset resets state and runs the wizard when there's no controlling tty" {
    have_tty && skip "has a controlling tty; the confirm prompt would block on read"
    run_zsh "$(extract chezsetup); chezsetup --reset"
    [ "$status" -eq 0 ]
    grep -q 'pull --ff-only' "$GIT_LOG"
    grep -q '^state reset --force' "$RESET_LOG"
    grep -q '^wizard ' "$WIZARD_LOG"
    [ ! -s "$INIT_LOG" ]  # not the fill-mode path
    [ ! -s "$APPLY_LOG" ] # reset mode never calls chezapply itself
}

@test "chezsetup -r is an alias for --reset" {
    have_tty && skip "has a controlling tty; the confirm prompt would block on read"
    run_zsh "$(extract chezsetup); chezsetup -r"
    [ "$status" -eq 0 ]
    grep -q '^state reset --force' "$RESET_LOG"
}

@test "chezsetup --reset forwards unrecognized args to wizard.sh" {
    have_tty && skip "has a controlling tty; the confirm prompt would block on read"
    run_zsh "$(extract chezsetup); chezsetup --reset -v"
    [ "$status" -eq 0 ]
    grep -q '^wizard -v' "$WIZARD_LOG"
}

@test "chezsetup --reset self-heals via _chez_run when wizard.sh is missing" {
    rm -f "$FAKE/scripts/bin/wizard.sh"
    run_zsh "$(extract chezsetup); chezsetup --reset"
    [ "$status" -eq 0 ]
    grep -q '_chez_run scripts/bin/wizard.sh' "$RUN_LOG"
    [ ! -s "$GIT_LOG" ]   # self-heal returns before the git pull
    [ ! -s "$RESET_LOG" ] # and before the destructive state reset
}

# ─── shared ──────────────────────────────────────────────────────────────────

@test "chezsetup --help prints usage and touches nothing" {
    run_zsh "$(extract chezsetup); chezsetup --help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: chezsetup"* ]] || return 1
    [[ "$output" == *"--reset"* ]] || return 1
    [ ! -s "$GIT_LOG" ]
    [ ! -s "$INIT_LOG" ]
    [ ! -s "$RESET_LOG" ]
    [ ! -s "$WIZARD_LOG" ]
}
