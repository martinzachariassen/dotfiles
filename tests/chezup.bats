#!/usr/bin/env bats
# Behavioural tests for scripts/bin/chezup.sh — the everyday "converge this Mac to
# the repo" verb (pull → preview drift → apply) behind the `chezup` zsh function.
#
# Why this exists:
#   chezup is the command run most often, so its control flow has to be exactly
#   right across the states it meets: a missing/renamed repo, a failed pull, a
#   clean tree, drifted files, a missing chezmoi, and DRY_RUN/YES overrides. None
#   of that is visible to `bash -n`. We run the REAL script with a fake source
#   repo and stubbed `git`/`chezmoi` on PATH, driving each branch by env var, and
#   assert both the exit code and that a real apply only happens when it should.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHEZUP="$REPO_ROOT/scripts/bin/chezup.sh"
    command -v bash >/dev/null 2>&1 || skip "bash not installed"

    # A fake source dir chezup points DOTFILES_DIR at. `.git` present = a repo.
    REPO="$(mktemp -d)"
    mkdir -p "$REPO/.git"

    # Stub bin dir (prepended to PATH) + the log the chezmoi stub writes to.
    STUBS="$(mktemp -d)"
    APPLY_LOG="$STUBS/apply.log"
    STATE="$STUBS/state"  # lets the git stub model a pull that advances HEAD
    mkdir -p "$STATE"

    # git stub: only the three subcommands chezup calls. By default HEAD is fixed
    # (before==after ⇒ an up-to-date pull). GIT_ADVANCE=1 makes `pull` drop a
    # marker so the post-pull rev-parse returns a DIFFERENT hash (a real advance);
    # GIT_PULL_RC forces a failed pull.
    cat >"$STUBS/git" <<EOF
#!/usr/bin/env bash
args="\$*"
case "\$args" in
    *rev-parse*)
        if [ -f "$STATE/pulled" ]; then echo "\${GIT_AFTER:-fedcba9876543210}"
        else echo "\${GIT_BEFORE:-abcdef1234567890}"; fi ;;
    *rev-list*)  echo "\${GIT_PULLED_COUNT:-0}" ;;
    *pull*)
        [ "\${GIT_ADVANCE:-0}" = 1 ] && : >"$STATE/pulled"
        exit "\${GIT_PULL_RC:-0}" ;;
    *)           exit 0 ;;
esac
EOF

    # chezmoi stub: `status` prints CHEZMOI_STATUS (empty = in sync); `apply`
    # records its args and honours CHEZMOI_APPLY_RC.
    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
if [ "\$1" = status ]; then
    printf '%s' "\${CHEZMOI_STATUS:-}"
    [ -n "\${CHEZMOI_STATUS:-}" ] && echo
    exit 0
fi
if [ "\$1" = apply ]; then
    shift
    printf 'apply %s\n' "\$*" >>"$APPLY_LOG"
    exit "\${CHEZMOI_APPLY_RC:-0}"
fi
exit 0
EOF
    chmod +x "$STUBS/git" "$STUBS/chezmoi"
}

teardown() {
    [ -n "${REPO:-}" ] && rm -rf "$REPO"
    [ -n "${STUBS:-}" ] && rm -rf "$STUBS"
    [ -n "${ISO:-}" ] && rm -rf "$ISO"
    return 0  # never let an unset-ISO short-circuit fail the test
}

# run_chezup — real script under stubbed PATH + a fake repo. Extra env in $1.
run_chezup() {
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" APPLY_LOG="$APPLY_LOG" \
        $1 bash "$CHEZUP"
}

# ─── Missing / broken repo ──────────────────────────────────────────────────

@test "chezup fails when the source dir has no git repo" {
    rm -rf "$REPO/.git"
    run_chezup ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"no git repo"* ]]
    [ ! -s "$APPLY_LOG" ]  # never reached apply
}

@test "chezup aborts when git pull --ff-only fails" {
    run_chezup "GIT_PULL_RC=1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"git pull --ff-only failed"* ]]
    [ ! -s "$APPLY_LOG" ]
}

@test "chezup fails when chezmoi is not on PATH" {
    # A PATH with the git stub + system coreutils but no chezmoi: the pull
    # succeeds, the drift check can't. chezmoi lives in Homebrew's bin (outside
    # /usr/bin:/bin), so this reliably hides it; skip in the unlikely event a
    # system-path chezmoi exists.
    PATH="/usr/bin:/bin" command -v chezmoi >/dev/null 2>&1 && skip "chezmoi on system PATH"
    local nochez="$STUBS/nochez"
    mkdir -p "$nochez"
    ln -s "$STUBS/git" "$nochez/git"
    run env PATH="$nochez:/usr/bin:/bin" DOTFILES_DIR="$REPO" GIT_PULL_RC=0 bash "$CHEZUP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"chezmoi is not on PATH"* ]]
}

# ─── Clean tree ─────────────────────────────────────────────────────────────

@test "chezup reports in-sync and exits 0 when nothing drifted" {
    run_chezup "CHEZMOI_STATUS="
    [ "$status" -eq 0 ]
    [[ "$output" == *"up to date"* ]]
    [[ "$output" == *"already in sync"* ]]
    [ ! -s "$APPLY_LOG" ]  # in sync ⇒ no apply
}

@test "chezup reports how many commits it pulled when the repo advanced" {
    # before != after ⇒ the 'pulled N commit(s)' branch instead of 'up to date'.
    run_chezup "GIT_ADVANCE=1 GIT_PULLED_COUNT=3 CHEZMOI_STATUS="
    [ "$status" -eq 0 ]
    [[ "$output" == *"pulled 3 commit"* ]]
    [[ "$output" != *"up to date"* ]]
}

@test "chezup fails loudly (exit 1) when its log.sh helper is missing" {
    # doctor.sh / bootstrap-auth.sh share this defensive guard: a checkout without
    # the sibling lib is broken, so fail rather than limp on with degraded output.
    ISO="$(mktemp -d)"
    mkdir -p "$ISO/scripts/bin"  # note: no scripts/lib ⇒ log.sh is absent
    cp "$CHEZUP" "$ISO/scripts/bin/chezup.sh"
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" bash "$ISO/scripts/bin/chezup.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]]
    [[ "$output" == *"log.sh"* ]]
}

# ─── Drift → apply ──────────────────────────────────────────────────────────

@test "chezup applies drifted files when confirmation is bypassed with YES=1" {
    run_chezup "CHEZMOI_STATUS=MM_dot_zshrc YES=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"drifted"* ]]
    [[ "$output" == *"chezup complete"* ]]
    grep -q 'apply --force' "$APPLY_LOG"
}

@test "chezup surfaces a failing apply as exit 1" {
    run_chezup "CHEZMOI_STATUS=M_dot_zshrc YES=1 CHEZMOI_APPLY_RC=1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"apply failed"* ]]
}

# ─── DRY_RUN: preview only, never mutate ────────────────────────────────────

@test "chezup with DRY_RUN=1 previews the apply without running it" {
    run_chezup "CHEZMOI_STATUS=M_dot_zshrc YES=1 DRY_RUN=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry-run"* ]]
    # The apply command is printed, not executed — so the stub logged nothing.
    [ ! -s "$APPLY_LOG" ]
}
