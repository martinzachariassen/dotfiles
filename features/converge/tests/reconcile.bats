#!/usr/bin/env bats
# Behavioural tests for chez reconcile, which orchestrates chez up and chez mirror
# (install, removal, DRY_RUN preview).
#
# reconcile.sh reaches its siblings by path, not as shell functions, so this
# builds a fake feature tree: the REAL reconcile.sh beside stub up.sh and
# ../brew/mirror.sh that announce themselves. Run order and argument passthrough
# are then assertable without brew or chezmoi.

setup() {
    load '../../../core/testing/helper'
    skip_unless bash

    FAKE="$BATS_TEST_TMPDIR/tree"
    mkdir -p "$FAKE/features/converge" "$FAKE/features/brew/lib" "$FAKE/core"
    cp "$REPO_ROOT/features/converge/reconcile.sh" "$FAKE/features/converge/reconcile.sh"
    cp "$REPO_ROOT/core/ui.sh" "$FAKE/core/ui.sh"
    cp "$REPO_ROOT/features/brew/lib/removals.sh" "$FAKE/features/brew/lib/removals.sh"

    cat >"$FAKE/features/converge/up.sh" <<'EOF'
#!/usr/bin/env bash
echo "CHEZUP $*"
exit "${CHEZUP_RC:-0}"
EOF
    cat >"$FAKE/features/brew/mirror.sh" <<'EOF'
#!/usr/bin/env bash
echo "CHEZMIRROR $*"
EOF
    chmod +x "$FAKE/features/converge/up.sh" "$FAKE/features/brew/mirror.sh"
}

run_reconcile() {
    run env CHEZUP_RC="${CHEZUP_RC:-0}" DRY_RUN="${DRY_RUN:-}" \
        bash "$FAKE/features/converge/reconcile.sh" "$@"
}

@test "chez reconcile runs chez up then chez mirror, in that order" {
    run_reconcile
    [ "$status" -eq 0 ]
    [[ "$output" == *CHEZUP* ]] || return 1
    [[ "$output" == *CHEZMIRROR* ]] || return 1
    # Install before prune: everything before the first CHEZMIRROR must include CHEZUP.
    [[ "${output%%CHEZMIRROR*}" == *CHEZUP* ]] || return 1
}

@test "chez reconcile forwards trailing args to chez up (→ chezmoi apply)" {
    run_reconcile -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"CHEZUP -v"* ]] || return 1
}

@test "chez reconcile under DRY_RUN previews via chez mirror -n and never removes" {
    DRY_RUN=1 run_reconcile
    [ "$status" -eq 0 ]
    [[ "$output" == *CHEZUP* ]] || return 1
    [[ "$output" == *"CHEZMIRROR -n"* ]] || return 1
}

@test "chez reconcile aborts before chez mirror when chez up fails" {
    CHEZUP_RC=4 run_reconcile
    [ "$status" -eq 4 ]
    [[ "$output" == *CHEZUP* ]] || return 1
    [[ "$output" != *CHEZMIRROR* ]] || return 1
}
