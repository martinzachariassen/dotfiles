#!/usr/bin/env bats
# Guards the one thing that makes every other suite in this repo meaningful.
#
# bats does not run test bodies under `set -e` — errexit is off, and failures
# are caught by a DEBUG trap instead. That trap sees commands: `false`, `[ ]`,
# `grep -q` and any helper function all fail their test correctly. It does not
# see `[[ ]]`, which is a shell *keyword*. So a bare `[[ ... ]]` only decides
# anything when it happens to be the last statement in the test — everywhere
# else it is decorative, and 226 of this suite's 385 were exactly that.
#
# Every bare `[[ ]]` therefore carries an explicit `|| return 1`. This test
# fails if one loses it.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "every bare [[ ]] assertion is gated with || return 1" {
    local offenders=()
    local f line stripped
    while IFS= read -r f; do
        while IFS= read -r line; do
            stripped="${line#"${line%%[![:space:]]*}"}"
            case "$stripped" in
                '[[ '*']]')
                    case "$stripped" in *'&&'* | *'||'*) continue ;; esac
                    offenders+=("$f: $stripped")
                    ;;
            esac
        done <"$f"
    done < <(find "$REPO_ROOT/tests" "$REPO_ROOT/features" -name '*.bats' 2>/dev/null)

    if [ "${#offenders[@]}" -gt 0 ]; then
        printf 'ungated (bats will not fail on these):\n' >&2
        printf '  %s\n' "${offenders[@]}" >&2
    fi
    [ "${#offenders[@]}" -eq 0 ]
}

# The premise above, asserted directly, so this file explains itself to anyone
# who doubts it rather than just asserting a style rule.
@test "bats really does ignore a non-final [[ ]] but honour [ ]" {
    local t="$BATS_TEST_TMPDIR/premise.bats"
    # Built from a variable rather than written literally, so the fixture's
    # deliberately-ungated assertion is not itself an offender above.
    local dbl='[[ "hello" == *"NOPE"* ]]'
    cat >"$t" <<INNER
@test "non-final double-bracket is ignored" {
    $dbl
    true
}
@test "non-final single-bracket is honoured" {
    [ 1 -eq 2 ]
    true
}
INNER
    run bats "$t"
    # The [[ ]] case passes despite a false assertion; the [ ] case fails.
    printf '%s\n' "$output" | grep -qE '^ok 1 ' || return 1
    printf '%s\n' "$output" | grep -qE '^not ok 2 '
}
