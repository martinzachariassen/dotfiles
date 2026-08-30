#!/usr/bin/env bats
# core/chez.sh — the dispatcher behind `chez <verb>`.
#
# Everything the command surface exposes comes from core/verbs.sh: which verbs
# exist, where each one runs, what `chez help` prints, and what the zsh
# completion offers. These tests drive the dispatcher from that table rather
# than from a second hand-written list, so a verb added to the table is covered
# here the moment it lands.

setup() {
    load '../core/testing/helper'
    CHEZ="$REPO_ROOT/core/chez.sh"
    # shellcheck source=../core/verbs.sh
    . "$REPO_ROOT/core/verbs.sh"
}

# Modules are passed in rather than read from this Mac, so the suite behaves
# the same on a laptop with every module on and on a CI runner with none.
chez() { run env CHEZ_MODULES="${MODULES-}" bash "$CHEZ" "$@"; }

# ─── resolution ──────────────────────────────────────────────────────────────

@test "every verb with a path points at a file that exists" {
    local bad=() v rel
    while IFS= read -r v; do
        rel="$(verbs_path "$v")"
        case "$rel" in "" | -) continue ;; esac
        [ -f "$REPO_ROOT/$rel" ] || bad+=("$v -> $rel")
    done < <(verbs_all)
    [ "${#bad[@]}" -eq 0 ] || printf 'verb points at a missing script: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

@test "every verb that runs something is executable as a bash script" {
    local bad=() v rel
    while IFS= read -r v; do
        rel="$(verbs_path "$v")"
        case "$rel" in "" | -) continue ;; esac
        bash -n "$REPO_ROOT/$rel" 2>/dev/null || bad+=("$v -> $rel")
    done < <(verbs_all)
    [ "${#bad[@]}" -eq 0 ] || printf 'verb target does not parse: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

@test "a verb execs its script and forwards every argument" {
    # `status` is read-only and takes a raw-passthrough path, so it is the
    # cheapest real verb to prove the hand-off with.
    local probe="$BATS_TEST_TMPDIR/probe"
    mkdir -p "$probe/features/converge" "$probe/core"
    cp "$REPO_ROOT/core/chez.sh" "$REPO_ROOT/core/verbs.sh" \
        "$REPO_ROOT/core/chezmoi-data.sh" "$probe/core/"
    cat >"$probe/features/converge/status.sh" <<'EOF'
#!/usr/bin/env bash
printf 'ran: %s\n' "$*"
EOF
    run env CHEZ_MODULES="" bash "$probe/core/chez.sh" status --raw -v
    [ "$status" -eq 0 ]
    [ "$output" = "ran: --raw -v" ]
}

@test "an unknown verb exits 2 and suggests the nearest one" {
    chez doctorr
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown verb: doctorr"* ]] || return 1
    [[ "$output" == *"did you mean: chez doctor"* ]] || return 1
}

@test "an unknown verb with no near match still points at the list" {
    chez frobnicate
    [ "$status" -eq 2 ]
    no_match 'did you mean' <<<"$output"
    [[ "$output" == *"chez help"* ]] || return 1
}

@test "cd is refused here, because only the shell function can change a directory" {
    chez cd
    [ "$status" -eq 1 ]
    [[ "$output" == *"has to run in your shell"* ]] || return 1
}

@test "a module-gated verb says which module it needs, not that it is unknown" {
    MODULES="" chez xcode
    [ "$status" -eq 1 ]
    [[ "$output" == *"needs the \`appleDev\` module"* ]] || return 1
    [[ "$output" == *"chez setup"* ]] || return 1
    no_match 'unknown verb' <<<"$output"
}

@test "a missing script is reported against the repo root, not silently skipped" {
    local probe="$BATS_TEST_TMPDIR/empty"
    mkdir -p "$probe/core"
    cp "$REPO_ROOT/core/chez.sh" "$REPO_ROOT/core/verbs.sh" \
        "$REPO_ROOT/core/chezmoi-data.sh" "$probe/core/"
    run env CHEZ_MODULES="" bash "$probe/core/chez.sh" up
    [ "$status" -eq 1 ]
    [[ "$output" == *"features/converge/up.sh is missing"* ]] || return 1
}

# ─── module gating ───────────────────────────────────────────────────────────
# CHEZ_MODULES set-but-empty is a real answer ("no modules on this Mac"), which
# is why the chezmoi fallback keys on unset rather than on empty.

@test "an ungated verb runs whatever the module set is" {
    local v
    for v in "" "appleDev claudeDistiller"; do
        MODULES="$v" chez help
        [ "$status" -eq 0 ]
        [[ "$output" == *"chez up"* ]] || return 1
    done
}

@test "help hides the gated verbs a Mac does not have, and shows the ones it does" {
    MODULES="" chez help
    no_match '^    chez (xcode|distill) ' <<<"$output"
    MODULES="appleDev" chez help
    [[ "$output" == *"chez xcode"* ]] || return 1
    no_match '^    chez distill ' <<<"$output"
    MODULES="appleDev claudeDistiller" chez help
    [[ "$output" == *"chez xcode"* ]] || return 1
    [[ "$output" == *"chez distill"* ]] || return 1
}

# ─── help ────────────────────────────────────────────────────────────────────
# The heredoc these replace was hand-maintained and checked in one direction
# only. Generated output cannot omit a verb, so what is worth pinning is the
# gating above and the shape below.

# ungated_verbs — the verbs every Mac has, sorted. Built in its own function
# because a `case` inside a command substitution inside a heredoc-fed test body
# is a parse error waiting to happen.
ungated_verbs() {
    local v m
    while IFS= read -r v; do
        m="$(verbs_module "$v")"
        if [ -z "$m" ] || [ "$m" = "-" ]; then printf '%s\n' "$v"; fi
    done < <(verbs_all) | sort
}

# Exactly four spaces: that is a verb entry. The knobs footer also opens with
# `chez mirror` / `chez up` at two spaces, and a looser anchor swallows those.
listed_verbs() { grep -oE '^    chez [a-z]+ ' <<<"$1" | awk '{print $2}'; }

@test "help lists every ungated verb exactly once, and nothing else" {
    MODULES="" chez help
    local listed expected
    expected="$(ungated_verbs)"
    listed="$(listed_verbs "$output" | sort)"
    [ "$listed" = "$expected" ] || {
        printf 'listed:\n%s\nexpected:\n%s\n' "$listed" "$expected" >&2
        return 1
    }
    # "exactly once" is the half a sorted comparison would miss.
    local dupes
    dupes="$(listed_verbs "$output" | sort | uniq -d)"
    [ -z "$dupes" ] || {
        printf 'listed twice: %s\n' "$dupes" >&2
        return 1
    }
}

@test "help prints group by group, each in table order" {
    MODULES="appleDev claudeDistiller" chez help
    # Help is group-major: the groups run in the order the table first mentions
    # them, and within a group the verbs keep their table order. Both halves are
    # derived from the table, so there is no second ordering to maintain — and
    # this is the exact property a rewritten group loop can silently break.
    local want got g
    while IFS= read -r g; do want="$want$(verbs_in_group "$g")"$'\n'; done < <(verbs_groups)
    want="$(printf '%s' "$want")"
    got="$(listed_verbs "$output")"
    [ "$want" = "$got" ] || {
        printf '%s\n' "expected order:" "$want" "help order:" "$got" >&2
        return 1
    }
}

@test "help never doubles a blank line" {
    # The group loop grew one once, and only reading the output catches it.
    MODULES="" chez help
    local i prev=x
    for ((i = 0; i < ${#lines[@]}; i++)); do
        if [ -z "${lines[$i]}" ] && [ -z "$prev" ]; then
            printf 'two blank lines at output line %s\n' "$i" >&2
            return 1
        fi
        prev="${lines[$i]}"
    done
}

@test "help documents the QUIET, DRY_RUN and YES knobs" {
    MODULES="" chez help
    [[ "$output" == *QUIET=1* ]] || return 1
    [[ "$output" == *DRY_RUN=1* ]] || return 1
    [[ "$output" == *YES=1* ]] || return 1
}

@test "no args and -h both print the help" {
    MODULES="" chez
    [ "$status" -eq 0 ]
    [[ "$output" == *"dotfiles commands"* ]] || return 1
    MODULES="" chez -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"dotfiles commands"* ]] || return 1
}

# ─── the completion feed ─────────────────────────────────────────────────────

@test "--verbs emits verb:summary for exactly the verbs help lists" {
    MODULES="appleDev" chez --verbs
    [ "$status" -eq 0 ]
    local from_verbs
    from_verbs="$(cut -d: -f1 <<<"$output" | sort)"
    MODULES="appleDev" chez help
    local from_help
    from_help="$(listed_verbs "$output" | sort)"
    [ "$from_verbs" = "$from_help" ] || {
        printf '%s\n' "--verbs:" "$from_verbs" "help:" "$from_help" >&2
        return 1
    }
}

@test "--verbs carries a summary for every verb, so completion can describe it" {
    MODULES="" chez --verbs
    local line
    while IFS= read -r line; do
        [ -n "${line#*:}" ] || {
            printf 'no summary in: %s\n' "$line" >&2
            return 1
        }
    done <<<"$output"
}
