#!/usr/bin/env bats
# Behavioural tests for `chez setup`, which merges the old chezreset/chezreinit
# into one verb: default mode fills in newly-added setup keys (chezmoi init +
# chez apply, keeping existing answers); --reset/-r replays first-time setup
# (state reset + re-run the wizard, overriding saved answers). Extracts the
# real function body from the committed template and runs it under zsh
# against stubbed git/chezmoi/cli.sh/apply.sh/_chez_run.

setup() {
    load '../../../core/testing/helper'
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"

    FAKE="$(mktemp -d)"
    mkdir -p "$FAKE/features/setup" "$FAKE/features/converge" "$FAKE/core"
    cp "$REPO_ROOT/features/setup/setup.sh" "$FAKE/features/setup/setup.sh"
    cp "$REPO_ROOT/core/ui.sh" "$FAKE/core/ui.sh"

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

    cat >"$FAKE/features/setup/cli.sh" <<EOF
#!/usr/bin/env bash
printf 'wizard %s\n' "\$*" >>"$WIZARD_LOG"
EOF
    chmod +x "$FAKE/features/setup/cli.sh"

    cat >"$FAKE/features/converge/apply.sh" <<EOF
#!/usr/bin/env bash
printf 'chez apply %s\n' "\$*" >>"$APPLY_LOG"
EOF
    chmod +x "$FAKE/features/converge/apply.sh"

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

have_tty() { { : </dev/tty; } >/dev/null 2>&1; }

run_setup() {
    run env PATH="$STUBS:$PATH" WIZARD_LOG="$WIZARD_LOG" \
        GIT_RC="${GIT_RC:-0}" CHEZMOI_INIT_RC="${CHEZMOI_INIT_RC:-0}" \
        CHEZMOI_RESET_RC="${CHEZMOI_RESET_RC:-0}" \
        bash "$FAKE/features/setup/setup.sh" "$@"
}

# ─── default mode: fill in new keys, never touch run-once state or the wizard ─

@test "chez setup (default) pulls, fills in new keys via chezmoi init, then applies" {
    run_setup
    [ "$status" -eq 0 ]
    grep -q 'pull --ff-only' "$GIT_LOG"
    grep -q '^init ' "$INIT_LOG"
    grep -q '^chez apply ' "$APPLY_LOG"
    [ ! -s "$RESET_LOG" ]  # never resets state in default mode
    [ ! -s "$WIZARD_LOG" ] # never touches the wizard in default mode
    [[ "$output" == *"filling in any new/unanswered setup keys only"* ]] || return 1
    [[ "$output" == *"chez setup --reset"* ]] || return 1
}

@test "chez setup (default) aborts before chezmoi init if git pull fails" {
    GIT_RC=7 run_setup
    [ "$status" -eq 7 ]
    [ ! -s "$INIT_LOG" ]
    [ ! -s "$APPLY_LOG" ]
}

@test "chez setup forwards unrecognized args to chez apply in default mode" {
    run_setup -v
    [ "$status" -eq 0 ]
    grep -q '^chez apply -v' "$APPLY_LOG"
}

# ─── --reset/-r: replay first-time setup ────────────────────────────────────
# The confirm prompt reads from /dev/tty directly (no gum branch), which a
# bats subprocess can't script input into — so these tests exercise the
# `[ -r /dev/tty ]` false branch (skips the prompt, proceeds unattended),
# matching how a CI/non-interactive run actually behaves. They skip on a
# real controlling tty rather than hang; see brew/tests/mirror.bats for the same pattern.

@test "chez setup --reset resets state and runs the wizard when there's no controlling tty" {
    have_tty && skip "has a controlling tty; the confirm prompt would block on read"
    run_setup --reset
    [ "$status" -eq 0 ]
    grep -q 'pull --ff-only' "$GIT_LOG"
    grep -q '^state reset --force' "$RESET_LOG"
    grep -q '^wizard ' "$WIZARD_LOG"
    [ ! -s "$INIT_LOG" ]  # not the fill-mode path
    [ ! -s "$APPLY_LOG" ] # reset mode never calls chez apply itself
}

@test "chez setup -r is an alias for --reset" {
    have_tty && skip "has a controlling tty; the confirm prompt would block on read"
    run_setup -r
    [ "$status" -eq 0 ]
    grep -q '^state reset --force' "$RESET_LOG"
}

@test "chez setup --reset forwards unrecognized args to wizard.sh" {
    have_tty && skip "has a controlling tty; the confirm prompt would block on read"
    run_setup --reset -v
    [ "$status" -eq 0 ]
    grep -q '^wizard -v' "$WIZARD_LOG"
}

# The self-heal for a missing script now belongs to _chez_run, which runs before
# this script does — tests/zshrc-wiring.bats asserts chez setup routes through it.
# What matters here is that a missing wizard cannot leave the machine half-reset:
# --reset clears chezmoi's run-once state, so failing after that and before the
# wizard would strand it.
@test "chez setup --reset does not reset state it cannot follow with a wizard" {
    rm -f "$FAKE/features/setup/cli.sh"
    run_setup --reset
    [ "$status" -ne 0 ]
    [ ! -s "$RESET_LOG" ]
}

# ─── shared ──────────────────────────────────────────────────────────────────

@test "chez setup --help prints usage and touches nothing" {
    run_setup --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: chez setup"* ]] || return 1
    [[ "$output" == *"--reset"* ]] || return 1
    [ ! -s "$GIT_LOG" ]
    [ ! -s "$INIT_LOG" ]
    [ ! -s "$RESET_LOG" ]
    [ ! -s "$WIZARD_LOG" ]
}
