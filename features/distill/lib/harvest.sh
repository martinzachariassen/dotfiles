#!/usr/bin/env bash
# Reading the transcripts.
#
# What to read and how far back. The sources are Claude's own session logs; this
# decides which of them are new since the cursor.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Harvest ──────────────────────────────────────────────────────────────────

# distill_session_files SINCE_ISO — transcripts that can still hold anything
# newer than SINCE, subagents excluded.
#
# The window is derived from the cursor rather than fixed, because a fixed one
# silently defeats the cursor. A Mac that slept for five days wakes with a
# five-day-old cursor, and `--since 7d` asks for a week outright; either way a
# transcript last written six days ago is exactly the file that must be read,
# and a two-day window drops it without a word. A file's mtime moves whenever a
# turn is appended, so mtime older than the cursor really does mean "nothing new
# in here" — the one day of slack absorbs clock skew and timezone edges.
#
# `find` is shadowed by bfs in this user's interactive shell, hence the full path.
distill_session_files() {
    local root expanded days since="${1:-}"
    days=2
    if [ -n "$since" ]; then
        days="$(distill_days_since "$since")"
        # 9999 is distill_days_since's answer for a timestamp it cannot parse;
        # never let that turn into a scan of every transcript ever written.
        if ! [ "$days" -ge 1 ] 2>/dev/null || [ "$days" -ge 9999 ]; then
            days=1
        fi
        days=$((days + 1))
    fi
    # Deduped by basename because transcriptRoots now lists two paths. Session
    # filenames are UUIDs, so the same basename under two roots is the same
    # session — reached twice via a symlink, or by a second Claude Code install
    # sharing a directory. Mapping it twice would bill twice for one session and
    # `hits` would not even notice, since it counts distinct session ids.
    while IFS= read -r root; do
        [ -n "$root" ] || continue
        expanded="$(distill_expand "$root")"
        [ -d "$expanded" ] || continue
        /usr/bin/find "$expanded" -type f -name '*.jsonl' \
            -not -path '*/subagents/*' -mtime -"${DISTILL_MTIME_DAYS:-$days}" 2>/dev/null
    done < <(distill_cfg_list transcriptRoots) | awk -F/ '!seen[$NF]++'
}

# ─── Sources ──────────────────────────────────────────────────────────────────
#
# Every precondition in this file used to guard an OUTPUT: can the memory dir be
# written, can the state dir, is the corpus pointed at the right remote. None
# guarded an input. So when transcriptRoots shipped pointing at a directory that
# has never existed, the nightly job read zero transcripts, recorded `status:
# ok`, and both --status and chezdoctor showed green — for its entire life.
#
# "Nothing was worth keeping last night" and "there is nowhere to read from" are
# different facts and only one of them is fine. These functions are what keeps
# them apart.

# distill_source_roots — the configured roots, tilde-expanded, one per line.
distill_source_roots() {
    local root
    while IFS= read -r root; do
        [ -n "$root" ] || continue
        distill_expand "$root"
    done < <(distill_cfg_list transcriptRoots)
}

# distill_source_count ROOT — transcripts under one root.
#
# Deliberately the same find predicate as distill_session_files, minus the mtime
# window: a count that can disagree with what the harvester actually opens is
# worse than no count, because it would make a broken run look explained.
distill_source_count() {
    [ -d "$1" ] || {
        echo 0
        return 0
    }
    /usr/bin/find "$1" -type f -name '*.jsonl' \
        -not -path '*/subagents/*' 2>/dev/null | wc -l | tr -d ' '
}

# distill_sources_ok — refuse to call a run with no inputs a quiet night.
#
# An EMPTY transcriptRoots list is not a failure: it is the deliberate "harvest
# nothing" the test suite runs on, and the honest reading of a list with nothing
# in it. What is never legitimate is a root that was configured and isn't there,
# or a set of roots that between them hold no transcript at all.
# 0 = go · 1 = there is nowhere to read from
distill_sources_ok() {
    local root total=0 n configured=0 missing=""

    while IFS= read -r root; do
        [ -n "$root" ] || continue
        configured=$((configured + 1))
        if [ ! -d "$root" ]; then
            missing="$missing $(distill_tilde "$root")"
            continue
        fi
        n="$(distill_source_count "$root")"
        total=$((total + n))
    done < <(distill_source_roots)

    # An empty list is only legitimate when it was really CONFIGURED empty. If
    # the config itself failed to load, distill_cfg_list returns nothing for
    # every key, and this guard would wave through precisely the outage it was
    # written to catch — a run that reads zero transcripts and calls it ok.
    if [ "$configured" -eq 0 ]; then
        distill_config_ok || return 1
        return 0
    fi

    # A missing root is NOT worth a warning on its own. transcriptRoots is a
    # CANDIDATE list — the two places Claude Code might keep transcripts — and
    # only one of them is ever real on a given machine, so the other is expected
    # to be absent. Warning about it would print the same line every night
    # forever, and a warning that is always on is one you stop reading. That is
    # the disease that let this job report green for its whole life; curing it
    # with a permanent yellow tick would be no cure. The absence only becomes a
    # fact worth stating when it is the reason there is nothing to read, below.
    [ "$total" -gt 0 ] && return 0

    if [ -n "$missing" ]; then
        distill_fail "no transcripts to read — configured root(s) do not exist:${missing}"
    else
        distill_fail "no transcripts under any configured root — nothing can be distilled"
    fi
    explain \
        "Claude Code writes transcripts to ~/.claude/projects. CLAUDE_CONFIG_DIR" \
        "moves settings and skills, not these. Check transcriptRoots in" \
        "src/.chezmoidata/distill.toml, then: chezdistill --status"
    return 1
}

# distill_filter FILE SINCE_ISO — the 16x reduction.
# Keeps typed human turns and assistant prose; drops tool traffic, thinking,
# sidechains and harness noise. ISO-8601 Z timestamps compare correctly as
# strings, so no date parsing is needed here.
distill_filter() {
    local file="$1" since="$2"
    jq -c --arg since "$since" '
        select(.timestamp != null and .timestamp > $since)
        | select((.isSidechain // false) | not)
        | select((.isMeta // false) | not)
        | select(.type == "assistant"
                 or (.type == "user" and .promptSource == "typed"))
        | { u: .uuid, t: .timestamp, r: (.message.role // .type),
            s: .sessionId, c: .cwd, g: .gitBranch,
            x: [ (.message.content // [])
                 | if type == "string" then .
                   else (.[] | select(.type == "text") | .text) end ] }
        | select((.x | length) > 0)
        | .x |= map(.[0:4000])
    ' "$file" 2>/dev/null
}

# distill_session_title FILE — the model-generated title; re-emitted, take the last.
distill_session_title() {
    jq -r 'select(.type == "ai-title") | .aiTitle' "$1" 2>/dev/null | tail -1
}

# distill_dedupe — drop entries resumed sessions re-serialise, oldest first.
# Slurps, which is safe only because the filter above has already cut the
# corpus to a few hundred KB per day.
distill_dedupe() {
    jq -s -c 'unique_by(.u) | sort_by(.t) | .[]'
}

# distill_turns — typed human turns in a filtered stream.
distill_turns() {
    jq -s '[.[] | select(.r == "user")] | length'
}
