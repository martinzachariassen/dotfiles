#!/usr/bin/env bats
# The feature registry's contract.
#
# features/*/feature.sh declares what a feature is; core/verbs.sh declares the
# command surface and which feature owns each verb. These tests keep the two
# honest, and keep the hand-written verb lists in sync with the table — the
# drift they exist to stop is the reason the list previously lived in five
# places with only one of them checked, in one direction.

setup() {
    load '../core/testing/helper'
    VERBS="$REPO_ROOT/core/verbs.sh"
    # shellcheck source=../core/verbs.sh
    . "$VERBS"
    # shellcheck source=../core/features.sh
    . "$REPO_ROOT/core/features.sh"
}

feature_list() { feature_names "$REPO_ROOT"; }

# ─── manifests ──────────────────────────────────────────────────────────────

@test "every feature directory has a manifest and a README" {
    local missing=() n d
    while IFS= read -r n; do
        d="$REPO_ROOT/features/$n"
        [ -f "$d/feature.sh" ] || missing+=("$n/feature.sh")
        [ -f "$d/README.md" ] || missing+=("$n/README.md")
    done < <(feature_list)
    [ "${#missing[@]}" -eq 0 ] || printf 'missing: %s\n' "${missing[@]}" >&2
    [ "${#missing[@]}" -eq 0 ]
}

@test "the skeleton features/README.md tells you to copy actually exists" {
    [ -f "$REPO_ROOT/features/_template/feature.sh" ] || return 1
    [ -f "$REPO_ROOT/features/_template/README.md" ] || return 1
    # ...and is scaffolding, not a feature: underscore-prefixed names are skipped.
    feature_list | grep -qx _template && {
        printf '_template is being registered as a feature\n' >&2
        return 1
    }
    return 0
}

@test "FEATURE_NAME matches the directory it sits in" {
    local bad=() n declared
    while IFS= read -r n; do
        declared="$(feature_field "$REPO_ROOT/features/$n" FEATURE_NAME)"
        [ "$declared" = "$n" ] || bad+=("$n declares '$declared'")
    done < <(feature_list)
    [ "${#bad[@]}" -eq 0 ] || printf 'mismatch: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

@test "a manifest has no side effects when sourced" {
    local n out
    while IFS= read -r n; do
        out="$(bash -c '. "$1/feature.sh"' _ "$REPO_ROOT/features/$n" 2>&1)"
        [ -z "$out" ] || {
            printf '%s/feature.sh produced output: %s\n' "$n" "$out" >&2
            return 1
        }
    done < <(feature_list)
}

@test "doctor orders are unique" {
    local dupes
    dupes="$(feature_doctor_order "$REPO_ROOT" | awk '{print $1}' | sort | uniq -d)"
    [ -z "$dupes" ] || printf 'duplicate doctor order: %s\n' "$dupes" >&2
    [ -z "$dupes" ]
}

@test "every FEATURE_MODULE names a real module in modules.toml" {
    local catalog bad=() n mod
    catalog="$(sed -n '/^\[moduleCatalog\]/,/^\[/p' "$REPO_ROOT/src/.chezmoidata/modules.toml" |
        sed -n 's/^ *\([A-Za-z][A-Za-z0-9]*\) *=.*/\1/p')"
    while IFS= read -r n; do
        mod="$(feature_field "$REPO_ROOT/features/$n" FEATURE_MODULE)"
        case "$mod" in "" | -) continue ;; esac
        printf '%s\n' "$catalog" | grep -qx "$mod" || bad+=("$n -> $mod")
    done < <(feature_list)
    [ "${#bad[@]}" -eq 0 ] || printf 'unknown module: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

# ─── the verb table ─────────────────────────────────────────────────────────

@test "every verb names a feature that exists, or the registry itself" {
    local bad=() v f
    while IFS= read -r v; do
        f="$(verbs_feature "$v")"
        [ "$f" = "-" ] && continue
        [ -d "$REPO_ROOT/features/$f" ] || bad+=("$v -> $f")
    done < <(verbs_all)
    [ "${#bad[@]}" -eq 0 ] || printf 'unknown feature: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

@test "every verb-level module gate names a real module" {
    local catalog bad=() v mod
    catalog="$(sed -n '/^\[moduleCatalog\]/,/^\[/p' "$REPO_ROOT/src/.chezmoidata/modules.toml" |
        sed -n 's/^ *\([A-Za-z][A-Za-z0-9]*\) *=.*/\1/p')"
    while IFS= read -r v; do
        mod="$(verbs_module "$v")"
        case "$mod" in "" | -) continue ;; esac
        printf '%s\n' "$catalog" | grep -qx "$mod" || bad+=("$v -> $mod")
    done < <(verbs_all)
    [ "${#bad[@]}" -eq 0 ] || printf 'unknown module: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

@test "no verb is listed twice" {
    local dupes
    dupes="$(verbs_all | sort | uniq -d)"
    [ -z "$dupes" ] || printf 'duplicate verb: %s\n' "$dupes" >&2
    [ -z "$dupes" ]
}

@test "every verb has a non-empty summary" {
    local bad=() v
    while IFS= read -r v; do
        [ -n "$(verbs_summary "$v")" ] || bad+=("$v")
    done < <(verbs_all)
    [ "${#bad[@]}" -eq 0 ] || printf 'no summary: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

# ─── the hand-written lists ─────────────────────────────────────────────────
#
# Two of the five places the verb list lived claim to be exhaustive: the
# chezhelp heredoc and docs/commands.md. Those are checked here, in both
# directions. README.md carries only the everyday verbs and the completion hook
# mentions verbs in context, so neither is a list and neither is enforced.

help_text() { sed -n '/^chezhelp() {/,/^}/p' "$ZSHRC"; }

@test "chezhelp lists every verb in the table" {
    local missing=() v legacy help
    help="$(help_text)"
    while IFS= read -r v; do
        legacy="$(verbs_legacy_name "$v")"
        [ -n "$legacy" ] || continue # a verb that does not exist yet
        printf '%s\n' "$help" | grep -qw -- "$legacy" || missing+=("$v ($legacy)")
    done < <(verbs_all)
    [ "${#missing[@]}" -eq 0 ] || printf 'absent from chezhelp: %s\n' "${missing[@]}" >&2
    [ "${#missing[@]}" -eq 0 ]
}

@test "chezhelp lists nothing that is not in the table" {
    local known extra=() word
    known="$(while IFS= read -r v; do verbs_legacy_name "$v"; done < <(verbs_all))"
    while IFS= read -r word; do
        printf '%s\n' "$known" | grep -qx "$word" || extra+=("$word")
        # `chezmoi` is the tool this repo drives, not one of its verbs.
    done < <(help_text | grep -oE '\bchez[a-z]+\b' | grep -vx chezmoi | sort -u)
    [ "${#extra[@]}" -eq 0 ] || printf 'in chezhelp but not the table: %s\n' "${extra[@]}" >&2
    [ "${#extra[@]}" -eq 0 ]
}

@test "docs/commands.md documents every verb in the table" {
    local missing=() v legacy
    while IFS= read -r v; do
        legacy="$(verbs_legacy_name "$v")"
        [ -n "$legacy" ] || continue
        grep -qw -- "$legacy" "$REPO_ROOT/docs/commands.md" || missing+=("$v ($legacy)")
    done < <(verbs_all)
    [ "${#missing[@]}" -eq 0 ] || printf 'absent from docs/commands.md: %s\n' "${missing[@]}" >&2
    [ "${#missing[@]}" -eq 0 ]
}

# ─── data files ─────────────────────────────────────────────────────────────

@test "every .chezmoidata file belongs to a feature or to core" {
    # chezmoi requires these under the source root, so they stay in
    # src/.chezmoidata/ rather than moving into their feature. This maps each to
    # its owner; the left column is renamed to match the right as the feature
    # moves. modules.toml is core-owned: it is the catalog every gate reads.
    local bad=() f base owner
    for f in "$REPO_ROOT"/src/.chezmoidata/*.toml; do
        base="$(basename "$f" .toml)"
        case "$base" in
            modules) continue ;;
            cleanup) owner=clean ;;
            packages) owner=brew ;;
            xcodes) owner=xcode ;;
            *) owner="$base" ;;
        esac
        [ -d "$REPO_ROOT/features/$owner" ] || bad+=("$base.toml -> $owner")
    done
    [ "${#bad[@]}" -eq 0 ] || printf 'unowned data file: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}
