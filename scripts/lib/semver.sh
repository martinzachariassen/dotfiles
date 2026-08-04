#!/usr/bin/env bash
# semver.sh — dependency-free semantic-version helpers (no sort -V, for CI parity).

# semver_extract STR — echo the first dotted-numeric run, e.g. "v2.52.0" -> "2.52.0".
semver_extract() {
    printf '%s\n' "$1" | grep -oE '[0-9]+(\.[0-9]+)*' | head -n1
}

# semver_lt A B — true if A < B; missing components count as 0, leading zeros are base-10 not octal.
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
