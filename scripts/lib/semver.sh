#!/usr/bin/env bash
# semver.sh — tiny semantic-version helpers shared across scripts.
#
# Sourced by scripts/doctor.sh; unit-tested by tests/semver.bats. Kept
# dependency-free (no sort -V) so behaviour is identical on macOS and Linux CI.

# semver_extract STR — echo the first dotted-numeric run in STR.
# e.g. "chezmoi version v2.52.0, commit abc" -> "2.52.0"
semver_extract() {
    printf '%s\n' "$1" | grep -oE '[0-9]+(\.[0-9]+)*' | head -n1
}

# semver_lt A B — exit 0 (true) if version A is strictly less than version B.
# Compares dot-separated numeric components left to right; missing trailing
# components count as 0, so "2.50" and "2.50.0" are equal. Leading zeros in a
# component are treated as base-10 (not octal).
semver_lt() {
    _a="$1"
    _b="$2"
    while [ -n "$_a$_b" ]; do
        _ah="${_a%%.*}"
        _bh="${_b%%.*}"
        case "$_a" in *.*) _a="${_a#*.}" ;; *) _a="" ;; esac
        case "$_b" in *.*) _b="${_b#*.}" ;; *) _b="" ;; esac
        _ah=$((10#${_ah:-0}))
        _bh=$((10#${_bh:-0}))
        [ "$_ah" -lt "$_bh" ] && return 0
        [ "$_ah" -gt "$_bh" ] && return 1
    done
    return 1
}
