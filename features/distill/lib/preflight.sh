#!/usr/bin/env bash
# Can this run happen at all.
#
# Every reason a run cannot proceed, checked before anything is written: the
# module, the CLI, the directories, the budget.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Preflight ────────────────────────────────────────────────────────────────

# distill_can_write DIR — create a file and remove it again.
#
# `[ -w ]` is not enough on macOS. Under TCC the POSIX bits on a protected
# directory say "writable" and the write syscall is still refused with EPERM,
# because a launchd agent has no access unless it has been granted explicitly.
# That gap is how a nightly run can spend weeks reporting success while every
# single write fails. Only an actual write tells the truth.
distill_can_write() {
    local dir="$1" probe
    [ -d "$dir" ] || return 1
    probe="$dir/.chezdistill-write-probe.$$"
    : >"$probe" 2>/dev/null || return 1
    rm -f "$probe" 2>/dev/null
    return 0
}

# distill_preflight — every precondition, checked before any processing.
# Exports DISTILL_MEMORY and DISTILL_STATE.
#
# Both are ordinary local directories the job owns outright, so they are simply
# created; there is no mount here that could be wrong, and nothing outside $HOME
# to be refused by macOS privacy protection.
# 0 = go · 1 = broken/unwritable (a real failure)
distill_preflight() {
    _distill_preflight_paths || return 1
    # Offline by construction: it reads the stamp the corpus already carries.
    # There is no URL comparison left to make — that was the guard a repo rename
    # walked straight through.
    distill_corpus_check_local || return 1
    return 0
}

# _distill_preflight_paths — the half `--status` still needs when the other half
# is what's broken. A status run that refuses to say anything because the corpus
# points at the wrong remote is a status run that can't help you fix it.
_distill_preflight_paths() {
    local d

    if ! command -v jq >/dev/null 2>&1; then
        fail "jq is required but not on PATH"
        return 1
    fi

    DISTILL_MEMORY="$(distill_expand \
        "$(distill_cfg memoryPath "$HOME/.config/claude/memory")")"
    DISTILL_STATE="$(distill_expand \
        "$(distill_cfg statePath "$HOME/.local/state/chezdistill")")"
    export DISTILL_MEMORY DISTILL_STATE

    # If these cannot be written there is nothing worth continuing for.
    mkdir -p "$DISTILL_MEMORY" "$DISTILL_STATE" 2>/dev/null || true
    for d in "$DISTILL_MEMORY" "$DISTILL_STATE"; do
        distill_can_write "$d" && continue
        fail "cannot write to $d"
        return 1
    done

    return 0
}

# distill_state_dir — every file no human reads.
# distill_memory_dir — what Claude loads.
#
# Both read the exported value when preflight has run and fall back to the
# configured path when it has not, so a caller that runs before preflight still
# lands where the config says rather than on the built-in default.
distill_state_dir() {
    [ -n "${DISTILL_STATE:-}" ] && {
        printf '%s\n' "$DISTILL_STATE"
        return 0
    }
    distill_expand "$(distill_cfg statePath "$HOME/.local/state/chezdistill")"
}

distill_memory_dir() {
    [ -n "${DISTILL_MEMORY:-}" ] && {
        printf '%s\n' "$DISTILL_MEMORY"
        return 0
    }
    distill_expand "$(distill_cfg memoryPath "$HOME/.config/claude/memory")"
}

# distill_pinned_file — the one hand-written file in the whole pipeline, and the
# only reason the state dir is worth backing up beyond convenience: everything
# else there can be re-derived or re-earned, and this cannot.
#
# It lives with the inputs, not with the output. Everything under the memory dir
# is generated and says so in its own header; a file you are told to edit sitting
# among files you are told never to edit is a trap.
distill_pinned_file() {
    printf '%s/Pinned.md\n' "$(distill_state_dir)"
}

# distill_seed_pinned — create it empty, once, and never touch it again.
#
# Every generated note tells you to fix a wrong rule by editing this file. Until
# something creates it, that instruction points at nothing, and the format it
# wants — plain bullets, copied verbatim — is not guessable from an absent file.
# The seed is one comment line because the whole file is pasted into MAIN.md and
# competes with the distilled rules for the same 6 KB.
distill_seed_pinned() {
    local f
    f="$(distill_pinned_file)"
    [ -e "$f" ] && return 0
    mkdir -p "$(dirname "$f")" || return 0
    printf '<!-- Hand-written. Copied into MAIN.md verbatim, never demoted. One `- ` rule per line. -->\n' \
        >"$f"
}
