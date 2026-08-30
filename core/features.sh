#!/usr/bin/env bash
# features.sh — the feature registry.
#
# Each directory under features/ carries a feature.sh manifest describing what
# the feature *is*: its name, its human title, the module that gates it, and
# where its checks belong in chezdoctor's running order. What it *does* lives in
# the sibling files (cli.sh, lib.sh, doctor.sh, hook.sh); which verbs it owns
# lives in core/verbs.sh, so the two never disagree.
#
# The manifest is data, not code: it is sourced in a subshell so nothing it sets
# can leak into a caller, and it must have no side effects.
#
# Bulk reads go through one grep over every manifest rather than a subshell per
# feature — measured at ~10.7 ms vs ~3.6 ms across fifteen features, which is
# the difference between a verb feeling instant and not.

[ -n "${__DOTFILES_FEATURES_SH:-}" ] && return 0
__DOTFILES_FEATURES_SH=1

# feature_root [DIR] — the repo root, found by walking up to .chezmoiroot.
feature_root() {
    local d="${1:-$PWD}"
    while [ "$d" != "/" ]; do
        [ -f "$d/.chezmoiroot" ] && {
            printf '%s\n' "$d"
            return 0
        }
        d="$(dirname "$d")"
    done
    return 1
}

# feature_dirs ROOT — every feature directory, in name order. Names beginning
# with "_" are scaffolding, not features: features/_template/ is a skeleton to
# copy and its manifest holds placeholders, so it must never be registered.
feature_dirs() {
    local d base
    for d in "$1"/features/*/; do
        base="$(basename "$d")"
        case "$base" in _*) continue ;; esac
        [ -f "$d/feature.sh" ] || continue
        printf '%s\n' "${d%/}"
    done
}

# feature_names ROOT — just the names.
feature_names() {
    local d
    while IFS= read -r d; do basename "$d"; done < <(feature_dirs "$1")
}

# feature_field DIR VAR — one manifest value, read without leaking into here.
feature_field() (
    # shellcheck source=/dev/null
    . "$1/feature.sh"
    eval "printf '%s\n' \"\${$2:-}\""
)

# feature_dir ROOT NAME — the directory for a feature, or exit 1.
feature_dir() {
    [ -f "$1/features/$2/feature.sh" ] || return 1
    printf '%s\n' "$1/features/$2"
}

# feature_active ROOT NAME DATA_JSON — true when the feature's module gate is
# satisfied. An empty or "-" FEATURE_MODULE means always active.
feature_active() {
    local dir mod
    dir="$(feature_dir "$1" "$2")" || return 1
    mod="$(feature_field "$dir" FEATURE_MODULE)"
    case "$mod" in "" | -) return 0 ;; esac
    command -v cm_has_module >/dev/null 2>&1 || return 1
    cm_has_module "$3" "$mod"
}

# feature_doctor_order ROOT — "ORDER NAME" per line, ascending. One grep for
# every manifest, then a numeric sort.
feature_doctor_order() {
    local line file order
    while IFS= read -r line; do
        file="${line%%:*}"
        order="${line#*FEATURE_DOCTOR_ORDER=}"
        order="${order%\"}"
        order="${order#\"}"
        [ -n "$order" ] || continue
        printf '%s %s\n' "$order" "$(basename "$(dirname "$file")")"
    done < <(grep -H '^FEATURE_DOCTOR_ORDER=' "$1"/features/[!_]*/feature.sh 2>/dev/null) |
        sort -n -k1,1
}
