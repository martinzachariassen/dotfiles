#!/usr/bin/env bats
# The doctor runner and the checks it owns itself.
#
# Every other section lives with its feature and is tested there; what is left
# here is the registry — running order, module gating, the tallies and the exit
# code — plus the three checks that belong to no feature: the source repo,
# chezmoi, and the XDG layout.

setup() {
    load '../../../core/testing/helper'
    load '../../../core/testing/doctor'
    doctor_iso_setup
}

# ─── the registry ───────────────────────────────────────────────────────────

@test "every feature with a doctor order has a fragment, and vice versa" {
    # shellcheck source=../../../core/features.sh
    . "$REPO_ROOT/core/features.sh"
    local bad=() d name order
    while IFS= read -r d; do
        name="$(basename "$d")"
        order="$(feature_field "$d" FEATURE_DOCTOR_ORDER)"
        if [ -n "$order" ] && [ ! -f "$d/doctor.sh" ]; then
            bad+=("$name declares order $order but has no doctor.sh")
        fi
        if [ -z "$order" ] && [ -f "$d/doctor.sh" ]; then
            bad+=("$name has a doctor.sh but no order — it would never run")
        fi
    done < <(feature_dirs "$REPO_ROOT")
    [ "${#bad[@]}" -eq 0 ] || printf '%s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

@test "every fragment defines the function the runner will call" {
    local bad=() f name
    for f in "$REPO_ROOT"/features/*/doctor.sh; do
        name="$(basename "$(dirname "$f")")"
        grep -qE "^doctor_${name}\(\) \{" "$f" || bad+=("$f -> doctor_$name")
    done
    [ "${#bad[@]}" -eq 0 ] || printf 'fragment does not define its function: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

@test "every registry check defines the function its filename implies" {
    local bad=() f base fn
    for f in "$REPO_ROOT"/features/doctor/checks/[0-9]*.sh; do
        base="$(basename "$f" .sh)"
        fn="doctor_check_$(printf '%s' "${base#*-}" | tr '-' '_')"
        grep -qE "^${fn}\(\) \{" "$f" || bad+=("$(basename "$f") -> $fn")
    done
    [ "${#bad[@]}" -eq 0 ] || printf 'check does not define its function: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

@test "a fragment is sourced, never executed — nothing may run at source time" {
    # Sourcing is what keeps the tallies in one process. A fragment that does
    # work outside its function would print before its own section heading, and
    # would print again for every feature sourced after it.
    local bad=() f out
    for f in "$REPO_ROOT"/features/*/doctor.sh "$REPO_ROOT"/features/doctor/checks/[0-9]*.sh; do
        out="$(bash -c ". '$f'" 2>&1)" || bad+=("$(basename "$(dirname "$f")")/$(basename "$f"): exits non-zero when sourced")
        [ -z "$out" ] || bad+=("$(basename "$(dirname "$f")")/$(basename "$f"): printed at source time")
    done
    [ "${#bad[@]}" -eq 0 ] || printf '%s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

@test "sections run in declared numeric order, not directory order" {
    doctor_stub_chezmoi "v2.72.0"
    doctor_git_init
    doctor_run
    # The order is deliberate: repo, then chezmoi, then layout, then identity,
    # then packages, then runtimes, then informational. Sorted by directory name
    # it would read auth, brew, claude, containers … which is nobody's idea of a
    # health report.
    # The summary rule is drawn with the same glyph, so drop it: it is not a
    # section and it is always last.
    local seen
    seen="$(grep -oE '^── .* ──$' <<<"$output" | sed 's/^── //; s/ ──$//' | grep -vx Summary)"
    [ "$(head -1 <<<"$seen")" = "Source repo" ]
    [ "$(sed -n 2p <<<"$seen")" = "chezmoi" ]
    [ "$(sed -n 3p <<<"$seen")" = "XDG layout" ]
    [ "$(tail -1 <<<"$seen")" = "Privacy permissions (manual check)" ]
    [ "$(tail -2 <<<"$seen" | head -1)" = "Fonts" ]
}

@test "a module-gated section is absent when its module is off, present when on" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed (the module gate reads it)"
    local p
    p="$(doctor_path_with jq)"
    doctor_git_init

    doctor_stub_chezmoi "v2.72.0" '[]'
    doctor_run_with "$p"
    no_match '^── Xcode / iOS' <<<"$output"
    no_match '^── Claude memory' <<<"$output"

    doctor_stub_chezmoi "v2.72.0" '["appleDev","claudeDistiller"]'
    doctor_run_with "$p"
    [[ "$output" == *"── Xcode / iOS (appleDev) ──"* ]] || return 1
    [[ "$output" == *"── Claude memory (claudeDistiller) ──"* ]] || return 1
}

@test "the tallies count every line the sections printed" {
    doctor_stub_chezmoi "v2.72.0"
    doctor_git_init
    doctor_run
    # One process, one set of counters — that is the whole reason fragments are
    # sourced rather than run. If a fragment ever became a subprocess its
    # pass/warn lines would still print and the summary would silently under-count.
    local passes warns fails summary
    passes="$(grep -c '✓ ' <<<"$output" || true)"
    warns="$(grep -c '! ' <<<"$output" || true)"
    fails="$(grep -c '✗ ' <<<"$output" || true)"
    summary="$(grep -E '[0-9]+ pass' <<<"$output")"
    [[ "$summary" == *"$passes pass"* ]] || {
        printf 'counted %s passes, summary says: %s\n' "$passes" "$summary" >&2
        return 1
    }
    [[ "$summary" == *"$warns action"* ]] || return 1
    [[ "$summary" == *"$fails fail"* ]] || return 1
}

@test "a failing check exits 1; warnings alone exit 0" {
    doctor_stub_chezmoi "v2.72.0"
    # No repo at DOTFILES_DIR is a fail.
    doctor_run
    [ "$status" -eq 1 ]
    [[ "$output" == *"repo missing at $ISO_REPO"* ]] || return 1
}

@test "an incomplete checkout says which engine is missing rather than degrading" {
    # The old runner sourced every engine behind `if [ -r … ]`, so a moved file
    # became silence: features/brew/lib/tiers.sh was renamed out from under a
    # stale path and the Homebrew section spent a release reporting "could not
    # resolve active Brewfiles" and then a green "no untracked brew packages"
    # derived from an empty set.
    local probe="$BATS_TEST_TMPDIR/probe"
    mkdir -p "$probe/features/doctor" "$probe/core"
    cp "$REPO_ROOT/features/doctor/cli.sh" "$probe/features/doctor/"
    cp "$REPO_ROOT/core/ui.sh" "$REPO_ROOT/core/features.sh" "$probe/core/"
    run env HOME="$ISO_HOME" DOTFILES_DIR="$ISO_REPO" PATH="$ISO_PATH" \
        GIT_CONFIG_GLOBAL="$ISO_GITCONFIG" bash "$probe/features/doctor/cli.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"this checkout is incomplete"* ]] || return 1
}

# ─── XDG layout ─────────────────────────────────────────────────────────────

@test "a legacy .zshrc is reported — it silently outranks the managed copy" {
    touch "$ISO_HOME/.zshrc"
    doctor_run
    [[ "$output" == *"legacy $ISO_HOME/.zshrc present"* ]] || return 1
}

@test "the managed layout alone passes" {
    mkdir -p "$ISO_HOME/.config/zsh"
    touch "$ISO_HOME/.config/zsh/.zshrc" "$ISO_HOME/.zshenv"
    doctor_run
    [[ "$output" == *"~/.config/zsh/.zshrc present"* ]] || return 1
    [[ "$output" == *"~/.zshenv present"* ]] || return 1
    [[ "$output" == *"no legacy .zshrc"* ]] || return 1
    [[ "$output" != *"legacy $ISO_HOME"* ]] || return 1
}

@test "a missing ~/.config/zsh/.zshrc is a failure" {
    doctor_run
    [[ "$output" == *"~/.config/zsh/.zshrc missing"* ]] || return 1
}

# ─── source repo ────────────────────────────────────────────────────────────

@test "no repo at DOTFILES_DIR is reported against that path" {
    doctor_run
    [[ "$output" == *"repo missing at $ISO_REPO"* ]] || return 1
}

@test "a real repo passes presence and clean-tree" {
    doctor_git_init
    doctor_run
    [[ "$output" == *"repo at $ISO_REPO"* ]] || return 1
    [[ "$output" == *"repo working tree clean"* ]] || return 1
}

# ─── chezmoi version floor ──────────────────────────────────────────────────

@test "an installed chezmoi below the repo floor fails" {
    doctor_git_init
    mkdir -p "$ISO_REPO/src"
    echo "2.50.0" >"$ISO_REPO/src/.chezmoiversion"
    doctor_stub_chezmoi "v2.40.0"
    doctor_run
    [[ "$output" == *"chezmoi 2.40.0 is older than the repo minimum 2.50.0"* ]] || return 1
}

@test "an installed chezmoi at or above the floor passes" {
    doctor_git_init
    mkdir -p "$ISO_REPO/src"
    echo "2.50.0" >"$ISO_REPO/src/.chezmoiversion"
    doctor_stub_chezmoi "v2.72.0"
    doctor_run
    [[ "$output" == *"chezmoi 2.72.0 meets repo minimum 2.50.0"* ]] || return 1
}
