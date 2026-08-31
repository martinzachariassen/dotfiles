#!/usr/bin/env bash
# Writing MAIN.md and Topics/.
#
# The memory tier, rendered from the corpus. Derived and disposable: --undo
# reverts the corpus and re-renders rather than reverting these files.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Rendering ────────────────────────────────────────────────────────────────
#
# One section, because one machine distilling one person's work has no second
# context to scope against. Rules that only apply somewhere say so in their own
# text, the way a hand-written rule in Pinned.md would.
#
# MAIN.md is rendered, never written by the model. Identical input yields a
# byte-identical file, so a re-render produces no diff and no commit.
#
# Eligibility for MAIN, all derived:
#   hits >= minHits          the promotion gate — one misreading can't become a rule
#   last_seen >= cutoff      still current; stale entries fall back to Topics
#
# Note this differs from the original plan, which demoted on
# "not reinforced for N days AND hits < minHits". That predicate can never fire:
# anything in MAIN already has hits >= minHits by the promotion gate, so the age
# rule would have been dead code and MAIN would only ever have grown. Age alone
# demotes here; `Pinned.md` is the channel for things that must never age out.

_DISTILL_MAIN_HEADING="Learned from past sessions"

distill_eligible() {
    local cutoff minhits
    minhits="$(distill_cfg minHits 2)"
    cutoff="$(date -u -v-"$(distill_cfg demoteAfterDays 21)"d +%Y-%m-%d 2>/dev/null ||
        date -u -d "$(distill_cfg demoteAfterDays 21) days ago" +%Y-%m-%d)"
    # `tonumber?` and the `// 0`, because last_seen is the first 10 characters of
    # a filename and nothing validates it. A bare tonumber on one stray file in
    # extracts/ aborts the WHOLE jq — not just that record — and every consumer
    # then sees an empty stream: MAIN.md renders with no rules at all, the write
    # succeeds, and the run reports ok. The tie-break is not worth that.
    #
    # 1000000 on both terms, not 100000: six digits is what a YYYYMMDD needs for
    # the decade to survive the modulo (2030-01-01 sorted BELOW 2029-12-31), and
    # the hits multiplier has to stay above the date term or recency would start
    # outranking the promotion gate.
    #
    # Buffered through a temp file rather than piped straight out, because a jq
    # that aborts halfway has already written the records before the bad one.
    # A truncated stream is worse than no stream: it looks exactly like a corpus
    # that legitimately holds fewer entries, and MAIN.md would be rendered from
    # it without a word. Emit all of it or none of it, and say so.
    local src out
    src="$(mktemp)"
    out="$(mktemp)"
    distill_derive >"$src"
    if ! jq -c --argjson minhits "$minhits" --arg cutoff "$cutoff" '
        . + { eligible: (.hits >= $minhits
                         and .last_seen >= $cutoff),
              score: (.hits * 1000000
                      + (((.last_seen | gsub("-";"") | tonumber?) // 0) % 1000000)) }' \
        "$src" >"$out" 2>/dev/null; then
        rm -f "$src" "$out"
        distill_fail "could not score the extract corpus — it may be corrupt"
        explain \
            "Every rendering decision reads this. Find the bad file with:" \
            "for f in \$(chez distill --status >/dev/null; echo ~/.local/state/chezdistill/extracts/*.json);" \
            "do jq -e . \"\$f\" >/dev/null || echo \"\$f\"; done"
        return 1
    fi
    cat "$out"
    rm -f "$src" "$out"
}

# The one line in MAIN that points at the tier below it. Every byte here is
# re-read in every session forever, so this is a single pointer at a guessable
# naming scheme rather than a link per rule — per-rule paths measured at roughly
# a sixth of the whole budget.
# `~` rather than the absolute path, everywhere a path is printed INTO MAIN.md:
# every byte here is re-read in every session forever, and the two lines below
# were together spending ~60 of them to say what `~` says. It reads the same to a
# person and to a model.
distill_tilde() {
    case "$1" in
        "$HOME"/*) printf '~%s\n' "${1#"$HOME"}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

_distill_topics_pointer() {
    printf 'Fuller explanations for the rules below live beside this file, in `%s/Topics/<Topic>.md`.\n' \
        "$(distill_tilde "$(distill_memory_dir)")"
}

# distill_render_main [OUTFILE] — deterministic; running it twice is a no-op.
distill_render_main() {
    local out="${1:-$(distill_memory_dir)/MAIN.md}"
    local pinned="$(distill_pinned_file)"
    local cap base tmp chosen line used scored n_eligible
    cap="$(distill_cfg mainCapBytes 6144)"

    # Score first, and bail before touching $out if scoring failed. MAIN.md is
    # derived, which cuts both ways: a render is free to run any time, and a
    # render from a broken corpus will happily replace a good file with an empty
    # one and report success. Refusing to write leaves the last good MAIN.md in
    # place, which is the safe stale state.
    scored="$(mktemp)"
    if ! distill_eligible >"$scored"; then
        rm -f "$scored"
        return 1
    fi

    tmp="$(mktemp)"
    chosen="$(mktemp)"
    mkdir -p "$(dirname "$out")"

    {
        printf '<!-- Generated by chezdistill. Do not edit: edit %s instead. -->\n\n' \
            "$(distill_tilde "$(distill_pinned_file)")"
        _distill_topics_pointer
        if [ -f "$pinned" ]; then
            printf '\n'
            cat "$pinned"
        fi
    } >"$tmp"

    base="$(wc -c <"$tmp" | tr -d ' ')"
    if [ "$base" -gt "$cap" ]; then
        distill_warn "Pinned.md alone exceeds the ${cap}B cap — nothing else will fit"
    fi

    # Reserve the section header up front, even though the section may end up
    # empty: what gets selected depends on the remaining budget, so reserving
    # unconditionally keeps the cap a guarantee rather than an estimate.
    used=$((base + ${#_DISTILL_MAIN_HEADING} + 3))
    # Highest score first, ties broken by id so the order is stable.
    jq -r 'select(.eligible) | [(.score|tostring), .topic, .id, .text] | @tsv' \
        <"$scored" |
        sort -t"$(printf '\t')" -k1,1nr -k3,3 |
        while IFS=$'\t' read -r _ topic id text; do
            line="- $text"
            [ $((used + ${#line} + 1)) -le "$cap" ] || break
            used=$((used + ${#line} + 1))
            printf '%s\t%s\t%s\n' "$topic" "$id" "$text"
        done >"$chosen"

    # The floor. An empty MAIN.md is legitimate on a young corpus — nothing has
    # cleared the promotion gate yet — but it is NOT legitimate when entries did
    # clear it and none of them made the file. That gap can only mean the byte
    # budget was exhausted by Pinned.md, and it is the exact shape of this job's
    # signature failure: a real result, silently replaced by nothing, reported ok.
    n_eligible="$(jq -r 'select(.eligible) | .id' <"$scored" | wc -l | tr -d ' ')"
    if [ "${n_eligible:-0}" -gt 0 ] && [ ! -s "$chosen" ]; then
        rm -f "$tmp" "$chosen" "$scored"
        distill_fail \
            "$n_eligible entr(ies) qualify for MAIN.md and none fit in ${cap}B — refusing to write an empty one"
        explain \
            "Pinned.md plus the header already fill the budget. Either trim" \
            "Pinned.md or raise mainCapBytes in src/.chezmoidata/distill.toml."
        return 1
    fi

    if [ -s "$chosen" ]; then
        printf '\n## %s\n\n' "$_DISTILL_MAIN_HEADING" >>"$tmp"
        sort -t"$(printf '\t')" -k1,1 -k2,2 "$chosen" |
            while IFS=$'\t' read -r _ _ text; do
                printf -- '- %s\n' "$text" >>"$tmp"
            done
    fi

    rm -f "$chosen" "$scored"
    if ! mv "$tmp" "$out" 2>/dev/null; then
        rm -f "$tmp"
        distill_fail "could not write $out"
        return 1
    fi

    used="$(wc -c <"$out" 2>/dev/null | tr -d ' ')"
    # Guard the comparison: a failed write leaves this empty, and `[ -le ]` on an
    # empty string is a shell error that reads as "MAIN.md is B, over the cap".
    [ -n "$used" ] || return 1
    [ "$used" -le "$cap" ] || distill_warn "MAIN.md is ${used}B, over the ${cap}B cap"
}

# distill_render_inbox — everything that did not earn a place in MAIN and why.
# Nothing here affects a session; it is the waiting room for the promotion gate.
distill_render_inbox() {
    local out="${1:-$(distill_memory_dir)/Candidates.md}"
    local minhits
    minhits="$(distill_cfg minHits 2)"
    mkdir -p "$(dirname "$out")"
    {
        printf '<!-- Generated by chezdistill. Entries here affect nothing. -->\n\n'
        printf '# Candidates\n\n'
        printf 'Seen in only one session so far. They reach MAIN.md once seen in\n'
        printf 'at least %s distinct session(s).\n' "$minhits"
        printf '\n## Awaiting a second sighting\n\n'
        distill_eligible |
            jq -r --argjson m "$minhits" \
                'select(.hits < $m)
                 | "- \(.text)  ·  \(.hits) hit(s), last seen \(.last_seen)"' |
            sort
        printf '\n## Demoted for age\n\n'
        printf 'Past the promotion gate but not reinforced lately, so they sit in `Topics/` instead.\n\n'
        distill_eligible |
            jq -r --argjson m "$minhits" \
                'select(.hits >= $m and (.eligible | not))
                 | "- \(.text)  ·  \(.hits) hit(s), last seen \(.last_seen)"' |
            sort
    } >"$out"
}

# distill_render_topics — the free tier, and the reason MAIN can afford to be
# terse. MAIN carries the rule (capped at 200 chars by the schema, because every
# byte is re-read in every session); the full `detail` lands here, next to MAIN,
# where it is read only when Claude looks a rule up and length costs nothing.
#
# Everything derived is written, not only what passed the promotion gate: a rule
# waiting for its second sighting is still worth reading once you have gone
# looking for the topic.
# distill_topic_slug TOPIC — the note name a topic is written to and linked by.
# A slash would send the write into a directory that does not exist and a wikilink
# to a note that does not exist; both fail silently, in opposite places.
distill_topic_slug() {
    printf '%s\n' "${1//\//-}"
}

distill_render_topics() {
    local dir="${1:-$(distill_memory_dir)/Topics}"
    local topic slug
    mkdir -p "$dir"

    distill_eligible | jq -r '.topic' | sort -u |
        while IFS= read -r topic; do
            [ -n "$topic" ] || continue
            # The model picks the topic freely, and it has picked names with a
            # slash in them ("Git/GitHub"). Left alone that redirects the write
            # into a directory that does not exist and the topic is silently lost.
            slug="$(distill_topic_slug "$topic")"
            {
                printf '<!-- Generated by chezdistill. -->\n\n# %s\n\n' "$topic"
                # Sorted inside jq: these records are multi-line, and piping
                # them through sort(1) would interleave lines across entries.
                distill_eligible |
                    jq -s -r --arg t "$topic" \
                        '[.[] | select(.topic == $t)]
                         | sort_by(.text)[]
                         | "## \(.text)\n\n\(.detail)\n\n*\(.hits) hit(s) · last seen \(.last_seen)*\n"'
            } >"$dir/$slug.md"
        done
}

# distill_render_all — every generated file. One entry point so a new one cannot
# be added to the nightly path and forgotten in --render.
distill_render_all() {
    distill_render_main
    distill_render_inbox
    distill_render_topics
}

# distill_extract_file DATE — this machine's share of one day of the corpus.
#
# Writes are always host-scoped; reads (distill_derive) take the whole directory,
# so a day that two Macs both contributed to still derives as one day.
distill_extract_file() {
    printf '%s/%s.%s.json\n' "$(distill_extracts_dir)" "$1" "$(distill_host)"
}
