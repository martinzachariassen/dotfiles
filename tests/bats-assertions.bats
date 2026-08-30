#!/usr/bin/env bats
# Guards the one thing that makes every other suite in this repo meaningful.
#
# bats runs test bodies with errexit *off* and detects failures with an ERR
# trap instead. bash's ERR trap fires for `[ ]`, `false`, `grep -q` and any
# helper function — but **not** for `[[ ]]`, which is a compound command the
# trap does not observe. So a bare `[[ ... ]]` is invisible to bats unless it is
# the last command in the body, whose exit status becomes the test's result.
# 226 of this suite's 385 were not last, and gated nothing.
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
@test "the ERR trap sees [ ], false and commands on every bash" {
    # The mechanism, proved directly rather than asserted. Not done by running
    # bats inside bats: bats 1.10 (what CI installs from apt; brew ships 1.14
    # locally) hands the child its own state and the child's tests become
    # "unknown test name", and scrubbing BATS_* to avoid that breaks bats' own
    # bootstrap.
    #
    # The probe is written from a variable so its deliberately-ungated
    # assertion is not itself an offender in the test above.
    local probe="$BATS_TEST_TMPDIR/errtrap.sh"
    local dbl='[[ "hello" == *"NOPE"* ]]'
    cat >"$probe" <<PROBE
fired=0
set -E
trap 'fired=\$((fired + 1))' ERR
$dbl
printf 'double %s\\n' "\$fired"
[ 1 -eq 2 ]
printf 'single %s\\n' "\$fired"
false
printf 'false %s\\n' "\$fired"
grep -q NOPE <<< "hello"
printf 'grep %s\\n' "\$fired"
PROBE
    run bash "$probe"
    [ "$status" -eq 0 ] || return 1

    # `[ ]`, `false` and a command always fire the trap. This is the half that
    # holds everywhere, and it is why those forms need no `|| return 1`.
    local d s2 f g
    d="$(printf '%s\n' "$output" | sed -n 's/^double //p')"
    s2="$(printf '%s\n' "$output" | sed -n 's/^single //p')"
    f="$(printf '%s\n' "$output" | sed -n 's/^false //p')"
    g="$(printf '%s\n' "$output" | sed -n 's/^grep //p')"
    [ "$((s2 - d))" -eq 1 ] || return 1
    [ "$((f - s2))" -eq 1 ] || return 1
    [ "$((g - f))" -eq 1 ] || return 1

    # `[[ ]]` is the version-dependent half, and the whole reason for the rule:
    # bash 3.2 (Apple's /bin/bash, which is what bats runs test bodies under on
    # macOS) does not fire the trap for it. bash 4.4+ does. So on a Mac a
    # non-final `[[ ]]` gates nothing while the same test gates correctly on
    # CI's Linux bash 5 — local green would not mean CI green.
    if [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
        { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
        [ "$d" -eq 0 ]
    else
        [ "$d" -eq 1 ]
    fi
}
