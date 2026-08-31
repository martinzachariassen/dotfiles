#!/usr/bin/env bash
# A corpus states its own identity.
#
# corpus.json — id and scope, never a URL. The scope is the leak boundary and is
# checked from the local copy, so the nightly guard stays offline.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Corpus identity ──────────────────────────────────────────────────────────
#
# A corpus says who it belongs to, in a tracked file that travels with it.
#
# The guard this replaces compared the origin URL against a table of known ones,
# which fails in the direction that actually happened: GitHub renamed the repo,
# the URL changed, and every string comparison still passed while the push had
# been failing for two days. A URL is a location, not an identity — so this file
# holds neither one nor anything derived from one.
#
# `scope` is the leak boundary: work extracts distilled into personal memory
# cannot be un-pushed, so a mismatch is a hard stop. `id` is the weaker question
# — "is this the same corpus I was attached to?" — which is what tells a rename
# (adopt it) from a different repo (refuse to merge without being asked).
#
# Schema 1 spelled the scope `profile`, back when the repo had a profile enum to
# borrow it from. Schema 2 writes `scope`; both are read, so an existing corpus
# keeps its identity and no Mac has to re-clone.

distill_corpus_file() {
    printf '%s/corpus.json\n' "$(distill_state_dir)"
}

# distill_corpus_new_id — unique enough, from tools both macOS and CI have.
# `uuidgen` is not on a bare ubuntu runner and /dev/urandom formatting differs;
# distill_sha is already used elsewhere here and works on both.
distill_corpus_new_id() {
    printf 'c-%s\n' "$(printf '%s|%s|%s|%s' \
        "$(distill_host)" "$(distill_iso_now)" "$$" "${RANDOM}${RANDOM}" |
        distill_sha)"
}

distill_corpus_field() {
    local f
    f="$(distill_corpus_file)"
    [ -r "$f" ] || return 0
    jq -r --arg k "$1" '.[$k] // empty' "$f" 2>/dev/null
}

distill_corpus_id() { distill_corpus_field id; }

# distill_corpus_scope — the stamp, from either schema. Schema 1 wrote `profile`.
distill_corpus_scope() {
    local v
    v="$(distill_corpus_field scope)"
    [ -n "$v" ] || v="$(distill_corpus_field profile)"
    printf '%s\n' "$v"
}

# distill_corpus_seed — stamp a corpus that has none. Written once, at creation,
# and never rewritten: two machines that both edited it would be the only way to
# manufacture a conflict in the one file whose whole job is to be agreed on.
distill_corpus_seed() {
    local f scope tmp
    f="$(distill_corpus_file)"
    scope="$(distill_scope)"

    # "Never rewritten" has one exception, and it is the reason this branch
    # exists: a corpus that carries NO scope. Both halves of the guard abstain
    # when either side is empty, so an unscoped corpus disarms the boundary —
    # here and on every Mac that later reads it through distill_remote_survey.
    # Left write-once that would be permanent, and setting a scope afterwards
    # would not repair it. An absent identity is not an identity to protect.
    #
    # Repaired in place rather than re-created: `id` is what the remote checks
    # match on, and a new one would read as a different corpus entirely.
    if [ -e "$f" ]; then
        [ -n "$scope" ] || return 0
        [ -n "$(distill_corpus_scope)" ] && return 0
        tmp="$f.scope.tmp"
        if jq --arg s "$scope" '.scope = $s' "$f" >"$tmp" 2>/dev/null; then
            mv "$tmp" "$f"
        else
            rm -f "$tmp"
        fi
        return 0
    fi

    mkdir -p "$(dirname "$f")" || return 0
    # The key is omitted rather than written empty, so "unscoped" is one state
    # and not two. distill_corpus_scope reads both the same way; the difference
    # is that an omitted key cannot be mistaken for an answer by a later reader.
    jq -n --arg id "$(distill_corpus_new_id)" \
        --arg s "$scope" \
        --arg c "$(distill_iso_now)" \
        --arg by "$(distill_host)" \
        '{schema: 2, id: $id, created: $c, createdBy: $by}
         + (if $s == "" then {} else {scope: $s} end)' \
        >"$f" 2>/dev/null || true
}

# distill_corpus_read_ref REF — the corpus.json a git ref carries, or empty when
# it has none (a corpus older than this file, which is adopted and stamped).
distill_corpus_read_ref() {
    git -C "$(distill_state_dir)" show "$1:corpus.json" 2>/dev/null
}

# distill_corpus_check_local — the offline half of the guard, and the one that
# runs every night. Reads the tracked file this machine already has, so it costs
# nothing and works at 01:00 with no network. 1 = do not proceed.
#
# It fires when a state dir came from somewhere else — restored from another
# Mac's backup, copied between scopes — and when the scope itself changed under
# an existing corpus, which is a real thing to do and needs both exits spelled
# out rather than a nightly refusal with no way forward.
distill_corpus_check_local() {
    local mine theirs
    mine="$(distill_scope)"
    theirs="$(distill_corpus_scope)"
    [ -n "$mine" ] && [ -n "$theirs" ] || return 0
    [ "$mine" = "$theirs" ] && return 0

    fail "the corpus at $(distill_state_dir) was stamped $theirs, but this is a $mine Mac"
    info "nothing will be distilled until that is settled. Either attach this Mac to its own corpus:"
    info "  chez distill --remote <$mine corpus url>"
    info "or start a fresh one here, keeping what is already backed up:"
    info "  chez distill --remote none"
    return 1
}

# distill_corpus_detached — did someone deliberately unhook this Mac?
#
# Kept in the state repo's own git config, because that is the only per-machine
# store that survives a chezmoi apply and is not the corpus itself. Without it
# `--remote none` would be undone by the next run, which re-adopts whatever the
# configured remote is.
distill_corpus_detached() {
    [ "$(git -C "$(distill_state_dir)" config --get distill.detached 2>/dev/null)" = "true" ]
}

# distill_extract_union A B OUT — one spelling of "these two shards are the same
# day, keep everything". Shared by the nightly merge and by an attach, so the
# rule that decides what a corpus contains cannot exist in two versions that
# disagree. Both inputs are {items: [...]}.
#
# Safe because hits counts DISTINCT SESSIONS at derive time: the same item
# arriving twice cannot inflate anything, and `unique` keeps the file byte-stable
# so re-running produces no commit.
distill_extract_union() {
    local a="$1" b="$2" out="$3" tmp
    tmp="$out.union.tmp"
    jq -s '{items: ((.[0].items // []) + (.[1].items // []) | unique)}' \
        "$a" "$b" >"$tmp" 2>/dev/null || {
        rm -f "$tmp"
        return 1
    }
    mv "$tmp" "$out" 2>/dev/null || {
        rm -f "$tmp"
        return 1
    }
    return 0
}
