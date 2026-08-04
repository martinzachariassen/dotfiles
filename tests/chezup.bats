#!/usr/bin/env bats
# Tests for scripts/bin/chezup.sh — the everyday "converge this Mac to the
# repo" verb (pull → preview drift → apply) behind the `chezup` zsh function.
#
# chezup runs most often, so its control flow must be exactly right across
# every state: missing/renamed repo, failed pull, clean tree, drifted files,
# missing chezmoi, DRY_RUN/YES overrides — none of which `bash -n` can see. We
# run the real script with a fake repo and stubbed git/chezmoi, driving each
# branch by env var.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHEZUP="$REPO_ROOT/scripts/bin/chezup.sh"
    command -v bash >/dev/null 2>&1 || skip "bash not installed"

    REPO="$(mktemp -d)"
    mkdir -p "$REPO/.git"

    STUBS="$(mktemp -d)"
    APPLY_LOG="$STUBS/apply.log"
    STATE="$STUBS/state"  # lets the git stub model a pull that advances HEAD
    mkdir -p "$STATE"

    # git stub: HEAD fixed by default (up-to-date pull). GIT_ADVANCE=1 drops a
    # marker so post-pull rev-parse returns a different hash; GIT_PULL_RC forces
    # a failed pull.
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

    # chezmoi stub: status prints CHEZMOI_STATUS; apply records args and
    # honours CHEZMOI_APPLY_RC.
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
    # chezmoi lives in Homebrew's bin (outside /usr/bin:/bin), so this
    # reliably hides it.
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
