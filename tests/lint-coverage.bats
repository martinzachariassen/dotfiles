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
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
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

@test "CI runs bats recursively so feature-owned suites are discovered" {
    grep -qE '^ *- run: bats -r tests/$' "$CI"
}

@test "shellcheck follows source directives relative to the script" {
    local rc="$REPO_ROOT/.shellcheckrc"
    [ -f "$rc" ]
    grep -qx 'external-sources=true' "$rc"
    grep -qx 'source-path=SCRIPTDIR' "$rc"
}
