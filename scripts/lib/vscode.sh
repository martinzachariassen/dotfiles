#!/usr/bin/env bash
# vscode.sh — pure helpers reconciling installed VS Code extensions against the manifest;
# no `code` calls, so the set logic is testable without VS Code installed.
# shellcheck disable=SC2034,SC2329

[ -n "${__DOTFILES_VSCODE_SH:-}" ] && return 0
__DOTFILES_VSCODE_SH=1

# Normalize for `comm`: strip comments/whitespace, lowercase (marketplace IDs are case-insensitive), drop blanks, sort -u.
vscode_normalize() {
    sed 's/#.*//; s/[[:space:]]//g' |
        tr '[:upper:]' '[:lower:]' |
        grep -v '^$' |
        sort -u
}

# vscode_read_manifest FILE [EXCLUDE...] — cleaned manifest IDs minus EXCLUDE (case-insensitive).
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

# vscode_untracked INSTALLED MANIFEST — installed but not in manifest (prune set); args normalized internally.
vscode_untracked() {
    comm -23 \
        <(printf '%s\n' "$1" | vscode_normalize) \
        <(printf '%s\n' "$2" | vscode_normalize)
}

# vscode_missing INSTALLED MANIFEST — in manifest but not installed (install set).
vscode_missing() {
    comm -13 \
        <(printf '%s\n' "$1" | vscode_normalize) \
        <(printf '%s\n' "$2" | vscode_normalize)
}
