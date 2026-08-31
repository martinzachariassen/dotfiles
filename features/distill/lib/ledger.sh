#!/usr/bin/env bash
# The extract corpus.
#
# The corpus itself: shards on disk, and the hit counts derived from them.
# Derived, never incremented — that is what makes --render, --since and a
# repeated nightly run idempotent.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Ledger ───────────────────────────────────────────────────────────────────
#
# There is one source of truth and it is the extract corpus: `extracts/<date>.json`,
# one file per day. Everything the renderer needs — the rule, its detail, hit
# counts, first and last seen — is DERIVED from it on every run rather than stored
# alongside it. Deriving is what makes `--since 7d`, `--render` and a repeated
# nightly run all safe to fire at will; a stored count would double on the second
# read of a day.
#
# An entry's identity is a hash of its normalised text, so the same fact extracted
# from two conversations collapses to one entry with two sightings.

distill_sha() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | cut -c1-12
    else
        sha256sum | cut -c1-12
    fi
}

# distill_entry_id TEXT — stable across re-runs.
distill_entry_id() {
    printf '%s' "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr -s '[:space:]' ' ' |
        sed -e 's/^ *//' -e 's/[ .,;:!?]*$//' |
        distill_sha
}

distill_extracts_dir() {
    printf '%s/extracts\n' "$(distill_state_dir)"
}

# distill_extract_date FILE — the day an extract file belongs to.
#
# The name is `<date>.<host>.json`, and the host is there so two Macs sharing one
# remote never write the same path: these files are merged in place, so a shared
# name is a rebase conflict on the only thing in the repo worth keeping. Reading
# the date as the leading 10 characters also accepts the older `<date>.json`,
# which is why no migration is needed — old files keep deriving exactly as before.
distill_extract_date() {
    local base
    base="$(basename "$1")"
    printf '%s\n' "${base:0:10}"
}

# distill_host — this machine, as a filename component.
distill_host() {
    local h
    h="$(hostname -s 2>/dev/null || echo unknown)"
    printf '%s\n' "${h//[^A-Za-z0-9_-]/-}"
}

# distill_derive — the single source of truth for every rendering decision.
# Aggregates the extract corpus into one NDJSON stream:
#   {id, text, kind, topic, hits, first_seen, last_seen}
#
# `hits` counts DISTINCT sessions, which is what the promotion gate is really
# asking: has this come up more than once, or is it one conversation's reading?
distill_derive() {
    local ex
    ex="$(distill_extracts_dir)"
    [ -d "$ex" ] || return 0

    /usr/bin/find "$ex" -type f -name '*.json' 2>/dev/null |
        while IFS= read -r f; do
            jq -c --arg date "$(distill_extract_date "$f")" \
                '.items[]? | {text, detail, kind, topic, session, date:$date}' \
                "$f" 2>/dev/null
        done |
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            printf '%s\n' "$item" |
                jq -c --arg id "$(distill_entry_id \
                    "$(printf '%s' "$item" | jq -r '.text')")" '. + {id:$id}'
        done |
        jq -s -c '
            group_by(.id)[]
            | { id: .[0].id,
                text: .[0].text,
                detail: (.[0].detail // ""),
                kind: .[0].kind,
                topic: (.[0].topic // "General"),
                hits: ([.[].session] | unique | length),
                last_seen: ([.[].date] | max),
                first_seen: ([.[].date] | min) }'
}

# distill_prune_extracts — age out the sensitive half of an old extract without
# touching the half the renderer needs.
#
# Deleting old extracts would be the obvious reading of `extractRetentionDays`,
# and it would be wrong: the extracts ARE the memory. `hits` and `first_seen` are
# derived from them on every render, so deleting a 90-day-old sighting drops an
# established rule back below the promotion gate and evicts it from MAIN.md — the
# corpus would silently forget exactly the rules that have been true longest.
#
# What actually deserves an expiry is the quoted `evidence` and the local `cwd`
# path. Those are dropped; text, detail, kind, topic, session and date stay, so
# the rendered memory is unchanged and a re-render is still byte-identical.
# `origin` and `host` go too — dead fields from the two-machine layout.
distill_prune_extracts() {
    local days cutoff f date tmp
    days="$(distill_cfg extractRetentionDays 90)"
    cutoff="$(date -u -v-"$days"d +%Y-%m-%d 2>/dev/null ||
        date -u -d "$days days ago" +%Y-%m-%d)"

    for f in "$(distill_extracts_dir)"/*.json; do
        [ -f "$f" ] || continue
        date="$(distill_extract_date "$f")"
        [ "$date" '<' "$cutoff" ] || continue
        jq -e '[.items[]? | select(has("evidence") or has("cwd")
               or has("origin") or has("host"))] | length > 0' \
            "$f" >/dev/null 2>&1 || continue
        tmp="$f.tmp"
        jq '{items: [.items[]? | del(.evidence, .cwd, .origin, .host)]}' \
            "$f" >"$tmp" 2>/dev/null && mv "$tmp" "$f" || rm -f "$tmp"
    done
}
