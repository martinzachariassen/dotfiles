#!/usr/bin/env bats
# The guard that makes every later file move safe.
#
# Shell scripts are linted from two places — .pre-commit-config.yaml (a regex)
# and .github/workflows/ci.yml (a git pathspec). Both are deliberately written
# in terms of tooling roots rather than individual directories, so that moving a
# script between scripts/, core/ and features/ cannot silently drop it from
# shellcheck/shfmt/bash -n. These tests pin the two to the same file set, and
# pin the mechanism itself so nobody reverts to hardcoded directory globs.

setup() {
    load '../core/testing/helper'
    PRECOMMIT="$REPO_ROOT/.pre-commit-config.yaml"
    CI="$REPO_ROOT/.github/workflows/ci.yml"
    command -v git >/dev/null 2>&1 || skip "git not installed"
}

# The set CI resolves: every tracked shell file outside chezmoi's source tree.
# .bash is in scope because bats' `load` convention names helpers that way.
tracked_shell_scripts() {
    git -C "$REPO_ROOT" ls-files -- '*.sh' '*.bash' ':!:src/**'
}

# The one `files:` pattern the three shell hooks share.
precommit_pattern() {
    sed -n "s/^ *files: '\(\^(install.*\)'$/\1/p" "$PRECOMMIT" | sort -u
}

@test "the three shell pre-commit hooks share a single files pattern" {
    run precommit_pattern
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
}

@test "every tracked shell script outside src/ matches the pre-commit pattern" {
    local pattern unmatched=()
    pattern="$(precommit_pattern)"
    [ -n "$pattern" ]
    local f
    while IFS= read -r f; do
        printf '%s\n' "$f" | grep -Eq "$pattern" || unmatched+=("$f")
    done < <(tracked_shell_scripts)
    if [ "${#unmatched[@]}" -gt 0 ]; then
        printf 'not covered by pre-commit: %s\n' "${unmatched[@]}" >&2
    fi
    [ "${#unmatched[@]}" -eq 0 ]
}

@test "the pre-commit pattern matches nothing CI would not lint" {
    local pattern extra=()
    pattern="$(precommit_pattern)"
    local ci_set f
    ci_set="$(tracked_shell_scripts)"
    while IFS= read -r f; do
        printf '%s\n' "$f" | grep -Eq "$pattern" || continue
        printf '%s\n' "$ci_set" | grep -Fqx "$f" || extra+=("$f")
    done < <(git -C "$REPO_ROOT" ls-files)
    if [ "${#extra[@]}" -gt 0 ]; then
        printf 'linted by pre-commit but not by CI: %s\n' "${extra[@]}" >&2
    fi
    [ "${#extra[@]}" -eq 0 ]
}

@test "CI resolves its shell file list from git, not from directory globs" {
    grep -q "git ls-files -z -- '\*\.sh' '\*\.bash' ':!:src/\*\*'" "$CI"
    # The old hardcoded form must not creep back in.
    ! grep -q 'scripts/bin/\*\.sh' "$CI"
}

@test "CI fails loudly if the pathspec resolves to nothing" {
    grep -q 'pathspec is wrong' "$CI"
}

@test "CI runs bats over both test roots, recursively" {
    grep -qE '^ *- run: bats -r tests/ features/$' "$CI"
}

@test "every .bats file in the repo is under a root CI actually runs" {
    # Adding a suite somewhere CI does not look loses its coverage silently:
    # the run stays green because the tests never execute. 50 feature-owned
    # tests were in exactly that state for the length of one commit.
    local roots stray=() f
    roots="$(sed -n 's/^ *- run: bats -r \(.*\)$/\1/p' "$CI")"
    [ -n "$roots" ] || return 1
    while IFS= read -r f; do
        local covered=1 r
        for r in $roots; do
            case "$f" in "${r%/}"/*) covered=0 ;; esac
        done
        [ "$covered" -eq 0 ] || stray+=("$f")
    done < <(git -C "$REPO_ROOT" ls-files -- '*.bats')
    if [ "${#stray[@]}" -gt 0 ]; then
        printf 'not run by CI (roots: %s):\n' "$roots" >&2
        printf '  %s\n' "${stray[@]}" >&2
    fi
    [ "${#stray[@]}" -eq 0 ]
}

@test "shellcheck follows source directives relative to the script" {
    local rc="$REPO_ROOT/.shellcheckrc"
    [ -f "$rc" ]
    grep -qx 'external-sources=true' "$rc"
    grep -qx 'source-path=SCRIPTDIR' "$rc"
}

# ── The required-check gate ──────────────────────────────────────────────────
# Branch protection on main requires exactly one context, `all checks`, and that
# job passes only if every other job did. It exists because a required context
# is pinned by NAME and a matrix job's name embeds its matrix values, so editing
# the render matrix retires a required check and blocks every later PR waiting
# for a name that can never report again.
#
# The cost of that indirection is a new failure mode: a job left out of the
# gate's `needs` still runs and still shows on the PR, it just stops being able
# to block a merge — green, and no longer gating. Same shape as a .bats suite
# CI never runs, and pinned here for the same reason.

# Job ids under `jobs:`. Scoped to that block because `on:` has keys at the
# same indent — push, pull_request, schedule are not jobs.
ci_job_ids() {
    awk '/^jobs:$/ { injobs = 1; next }
         injobs && /^[^ ]/ { injobs = 0 }
         injobs && /^  [a-z][a-z0-9_-]*:$/ { sub(":", ""); print $1 }' "$CI"
}

# The ids listed under the gate job's `needs:`.
ci_gate_needs() {
    awk '/^  gate:$/ { ingate = 1; next }
         ingate && /^  [a-z]/ { exit }
         ingate && /^    needs:$/ { inneeds = 1; next }
         inneeds && /^      - / { print $2; next }
         inneeds { exit }' "$CI"
}

@test "the gate job is named what branch protection requires" {
    # Renaming it silently un-gates main: the ruleset keeps waiting for the old
    # context and nothing goes red. Change both, in the same PR, or neither.
    grep -qx '  gate:' "$CI"
    grep -qx '    name: all checks' "$CI"
}

@test "the gate depends on every other job in the workflow" {
    local needs missing=() id
    needs="$(ci_gate_needs)"
    [ -n "$needs" ] || return 1
    while IFS= read -r id; do
        [ "$id" = "gate" ] && continue
        printf '%s\n' "$needs" | grep -Fqx "$id" || missing+=("$id")
    done < <(ci_job_ids)
    if [ "${#missing[@]}" -gt 0 ]; then
        printf 'job not in `gate.needs`, so it cannot block a merge: %s\n' \
            "${missing[@]}" >&2
    fi
    [ "${#missing[@]}" -eq 0 ]
}

@test "every job the gate needs actually exists" {
    local ids stray=() id
    ids="$(ci_job_ids)"
    while IFS= read -r id; do
        printf '%s\n' "$ids" | grep -Fqx "$id" || stray+=("$id")
    done < <(ci_gate_needs)
    if [ "${#stray[@]}" -gt 0 ]; then
        printf 'needed by `gate` but no such job: %s\n' "${stray[@]}" >&2
    fi
    [ "${#stray[@]}" -eq 0 ]
}

@test "the gate runs even when a job it needs has failed" {
    # Without `if: always()` a failed dependency skips the gate instead of
    # failing it, and a skipped required check reports nothing at all — the
    # merge blocks on a pending context rather than on a red one.
    grep -qx '    if: always()' "$CI"
}

@test "the gate fails on a failed or cancelled job and tolerates a skipped one" {
    # render-macos is schedule-only and pr-title is PR-only, so on any given
    # event one of them is skipped by design. Treating skipped as failure would
    # make the gate permanently red.
    grep -qF "*' failure '* | *' cancelled '*) exit 1 ;;" "$CI"
    no_match "skipped.*exit 1" "$CI"
}
