#!/usr/bin/env bash
# vscode.sh — pure helpers for reconciling installed VS Code extensions against
# the repo manifest (packages/vscode-extensions.txt), which is the source of truth.
#
# Sourced by:
#   - src/.chezmoiscripts/run_onchange_after_03-vscode.sh.tmpl (install + prune)
#   - scripts/bin/doctor.sh (read-only drift report)
# Unit-tested by tests/vscode.bats.
#
# Kept dependency-free (only sed/tr/grep/sort/comm) so behaviour is identical on
# macOS and Linux CI, and deliberately free of any `code` call so the set logic
# is testable without VS Code installed. Every function is pure: it takes
# newline-delimited lists (or a file path) and echoes a result — it never invokes
# `code` or mutates state. Callers supply the installed set (from
# `code --list-extensions`) and the manifest path.
#
# Locale note: the manifest lists the Norwegian dictionary
# (streetsidesoftware.code-spell-checker-norwegian-bokmal) unconditionally, but
# it is only wanted when the `locale` module is on. vscode_read_manifest takes an
# optional list of IDs to exclude so the hook (via its template guard) and doctor
# (via chezmoi data) derive the SAME effective allowed-set — used for both the
# install and the prune direction, so nothing is installed that would then be
# pruned, or vice versa.
#
# Functions are consumed by sourcing callers, so they read as "unused" and
# "unreachable" within this file. Suppress those false positives.
# shellcheck disable=SC2034,SC2329

# Source guard so re-sourcing is cheap and safe.
[ -n "${__DOTFILES_VSCODE_SH:-}" ] && return 0
__DOTFILES_VSCODE_SH=1

# vscode_normalize — clean a newline-delimited list of extension IDs read on
# stdin: strip `#` comments, remove all whitespace (valid IDs are
# "publisher.name" with none), lowercase, drop blank lines, sort -u. Lowercasing
# matters because marketplace IDs are case-insensitive and `code
# --list-extensions` can report publisher case differently than the manifest;
# folding to lowercase makes the set comparison stable. Sorted output feeds `comm`.
vscode_normalize() {
    sed 's/#.*//; s/[[:space:]]//g' |
        tr '[:upper:]' '[:lower:]' |
        grep -v '^$' |
        sort -u
}

# vscode_read_manifest FILE [EXCLUDE...] — echo the cleaned, effective extension
# IDs from the manifest FILE, dropping any EXCLUDE IDs (case-insensitively). A
# missing FILE yields no output. Used by both the install and prune directions so
# they agree on the source-of-truth set.
vscode_read_manifest() {
    local file="$1"
    shift
    [ -f "$file" ] || return 0

    local manifest ex
    manifest="$(vscode_normalize <"$file")"
    for ex in "$@"; do
        ex="$(printf '%s' "$ex" | tr '[:upper:]' '[:lower:]')"
        manifest="$(printf '%s\n' "$manifest" | grep -vxF "$ex" || true)"
    done
    printf '%s\n' "$manifest" | grep -v '^$' || true
}

# vscode_untracked INSTALLED MANIFEST — IDs installed locally but NOT in the
# manifest (the prune set). Both args are newline-delimited lists; each is
# normalized internally, so the caller can pass raw `code --list-extensions`
# output for INSTALLED.
vscode_untracked() {
    comm -23 \
        <(printf '%s\n' "$1" | vscode_normalize) \
        <(printf '%s\n' "$2" | vscode_normalize)
}

# vscode_missing INSTALLED MANIFEST — IDs in the manifest but NOT installed
# locally (what the install direction would add / doctor reports as missing).
vscode_missing() {
    comm -13 \
        <(printf '%s\n' "$1" | vscode_normalize) \
        <(printf '%s\n' "$2" | vscode_normalize)
}
