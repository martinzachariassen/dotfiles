#!/usr/bin/env bash
# vscode.sh — pure helpers reconciling installed VS Code extensions against the
# repo manifest (packages/vscode-extensions.txt). Dependency-free and free of any
# `code` call so the set logic is testable without VS Code installed.
# shellcheck disable=SC2034,SC2329

[ -n "${__DOTFILES_VSCODE_SH:-}" ] && return 0
__DOTFILES_VSCODE_SH=1

# Strip comments/whitespace, lowercase (marketplace IDs are case-insensitive and
# `code --list-extensions` may differ in case), drop blanks, sort -u for `comm`.
vscode_normalize() {
    sed 's/#.*//; s/[[:space:]]//g' |
        tr '[:upper:]' '[:lower:]' |
        grep -v '^$' |
        sort -u
}

# vscode_read_manifest FILE [EXCLUDE...] — cleaned manifest IDs minus EXCLUDE
# (case-insensitive). Excludes let install and prune agree on the effective set
# (e.g. the Norwegian dictionary only when the `locale` module is on).
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

# vscode_untracked INSTALLED MANIFEST — installed but not in manifest (prune set).
# Both args normalized internally, so raw `code --list-extensions` is fine.
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

# vscode_orphaned_home_dirs ROWS INSTALLED — ROWS is "dir<TAB>extension" lines (one
# per extension-owned HOME dir, from cleanup.owners), INSTALLED is raw
# `code --list-extensions` output. Emit each DIR whose owning extension is NOT
# installed. Pure: no `code` call, no filesystem — hook 03b feeds it live data and
# performs the removal. Extension IDs are lowercased on both sides (marketplace IDs
# are case-insensitive), so case drift can't make an installed extension look gone.
vscode_orphaned_home_dirs() {
    local rows="$1" installed row dir ext tab
    tab="$(printf '\t')"
    installed="$(printf '%s\n' "$2" | vscode_normalize)"
    while IFS= read -r row; do
        case "$row" in *"$tab"*) ;; *) continue ;; esac
        dir="${row%%"$tab"*}"
        ext="${row#*"$tab"}"
        [ -n "$dir" ] && [ -n "$ext" ] || continue
        ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
        printf '%s\n' "$installed" | grep -qxF -- "$ext" && continue
        printf '%s\n' "$dir"
    done <<EOF
$rows
EOF
}
