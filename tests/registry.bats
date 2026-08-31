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
# The verb list lived in five hand-synced places, and nothing checked four of
# them. Three are generated now — `chez help`, the completion feed and dispatch
# all read the table — so what is left to police is the prose. docs/commands.md
# claims to be exhaustive, so it is checked in both directions; README.md
# carries only the everyday verbs and the completion hook mentions verbs in
# context, so neither is a list and neither is enforced.

@test "docs/commands.md documents every verb in the table" {
    local missing=() v
    while IFS= read -r v; do
        grep -qF -- "chez $v" "$REPO_ROOT/docs/commands.md" || missing+=("$v")
    done < <(verbs_all)
    [ "${#missing[@]}" -eq 0 ] || printf 'absent from docs/commands.md: %s\n' "${missing[@]}" >&2
    [ "${#missing[@]}" -eq 0 ]
}

# The aliases are retired, so a doc that still tells you to run `chezup` is
# telling you to run something that does not exist. This is the guard that makes
# the retirement real rather than aspirational.
#
# It looks for a retired name in the two shapes that mean "type this": wrapped in
# backticks, or opening a line inside a shell block. Prose and output samples are
# left alone on purpose — `chezdistill` is what the nightly job is *called*, it
# prints `── chezdistill runs ──` as a heading, and its state lives in
# ~/.local/state/chezdistill. Renaming the job is not what retiring an alias means.
@test "no retired name is still offered as something to type" {
    local bad=() v retired hits
    while IFS= read -r v; do
        retired="$(verbs_retired_name "$v")"
        [ -n "$retired" ] || continue
        # `dotfiles` is exempt: it is the repo's own name and an ordinary English
        # word here ("untracked dotfiles"), so no textual rule separates a
        # retired command from prose. The other fifteen are unambiguous.
        [ "$retired" = "dotfiles" ] && continue
        # core/verbs.sh is where the retired names are *defined*, so it is not a
        # place they are being suggested.
        hits="$(grep -rInE "(\`${retired}([ \`]|$)|^ *${retired}( |$))" \
            --exclude=verbs.sh --exclude-dir=tests \
            "$REPO_ROOT/docs" "$REPO_ROOT/README.md" "$REPO_ROOT/CLAUDE.md" \
            "$REPO_ROOT/features" "$REPO_ROOT/core" 2>/dev/null || true)"
        [ -z "$hits" ] || bad+=("$retired -> $(printf '%s' "$hits" | head -2 | tr '\n' ' ')")
    done < <(verbs_all)
    [ "${#bad[@]}" -eq 0 ] || printf 'retired name still offered: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

# ─── the retired profile axis ───────────────────────────────────────────────
#
# v1.0 removed the `profile` enum. "No code mentions it" would be the guard you
# want, and it is not available: the migration has to read the key to retire it,
# the resolver has to detect it to fail closed, and the distiller has to fall
# back to it or every Mac set up before `memoryScope` loses its corpus identity.
#
# So the guard is an allow-list. Every file below is a place the key is read,
# written or explained on purpose; anywhere else is a gate that came back. The
# list is meant to shrink — when the migration is retired, most of it goes with
# it — and shrinking it is an edit here, which is the point.
#
# Scoped to code. Prose is excluded because the docs discuss the retirement at
# length and a doc rewrite is not a regression.
@test "only the migration's own files still mention the profile" {
    local allowed=(
        # The migration itself: the hook, its engine, and the config template
        # that keeps passing the key through until the engine removes it.
        "src/.chezmoi.toml.tmpl"
        "src/.chezmoiscripts/run_once_before_00b-retire-work-profile.sh.tmpl"
        "features/brew/migrate-work-profile.sh"
        # Fail-closed: both refuse to answer while the key is present, because
        # an un-migrated config resolves to a removal set that is far too broad.
        "features/brew/lib/tiers.sh"
        "features/brew/doctor.sh"
        # The corpus leak boundary. A Mac stamped before `memoryScope` existed
        # keeps its scope only by falling back to what the profile used to be.
        "features/distill/lib/config.sh"
        "features/distill/lib/corpus.sh"
        "features/distill/lib/attach.sh"
        "features/setup/cli.sh"
        "features/sign/cli.sh"
        # Tombstones: each says what its gate used to be and why it is now data.
        "src/.chezmoidata/brew.toml"
        "src/.chezmoidata/modules.toml"
        "src/.chezmoidata/storecode.toml"
        "src/.chezmoiscripts/run_onchange_after_05-storecode.sh.tmpl"
        "features/storecode/hook.sh"
        # The un-migrated render path, exercised on demand by LEGACY_PROFILE.
        "scripts/ci/render-check.sh"
        # Not this profile: an Xcode simulator runtime's device profile.
        "features/xcode/probe.sh"
    )

    # Line-level, not file-level: `grep -w` counts `.` as a word boundary, so
    # the dotfiles named .profile / .zprofile / .bash_profile all match. Those
    # are files in $HOME, not the retired key, and they are named all over the
    # XDG-migration checks.
    local found bad=() f rel
    found="$(grep -rnw profile \
        --include='*.sh' --include='*.tmpl' --include='*.toml' --include='*.zsh' \
        --exclude-dir=tests \
        "$REPO_ROOT/src" "$REPO_ROOT/core" "$REPO_ROOT/features" \
        "$REPO_ROOT/scripts" 2>/dev/null |
        grep -vE '(/\.profile|\.bash_profile|\.zprofile|dot_profile)' |
        cut -d: -f1 | sort -u || true)"

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        rel="${f#"$REPO_ROOT"/}"
        case " ${allowed[*]} " in *" $rel "*) continue ;; esac
        bad+=("$rel")
    done <<<"$found"

    [ "${#bad[@]}" -eq 0 ] || printf 'profile is read somewhere new: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]

    # …and the list may not rot in the other direction either: an entry whose
    # file stopped mentioning the key is a line to delete, not to keep for
    # safety. Otherwise the list only ever grows and stops meaning anything.
    for rel in "${allowed[@]}"; do
        case "$found" in *"$REPO_ROOT/$rel"*) continue ;; esac
        bad+=("$rel (allow-listed but clean — drop the entry)")
    done
    [ "${#bad[@]}" -eq 0 ] || printf '%s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
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
