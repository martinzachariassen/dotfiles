#!/usr/bin/env bash
# --runs and --stats.
#
# The other read-only answers: a row per night, and the corpus funnel.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Run history ──────────────────────────────────────────────────────────────
#
# runs.jsonl already kept 90 days of records and nothing read it but --status,
# which shows the last one. One record is enough to answer "did it run last
# night" and useless for "has it been doing anything all week" — which is the
# question that would have caught the empty-transcriptRoots bug on night two.

# distill_runs [N] — the last N runs, newest last so the eye lands on it.
distill_runs() {
    local n="${1:-14}" f rows failed quiet
    f="$(distill_run_file)"
    s_section "chezdistill runs"

    if [ ! -s "$f" ]; then
        s_note "no run recorded yet — the first run creates one"
        return 0
    fi

    printf '     %s%-16s  %-8s  %-6s  %9s  %5s  %6s  %7s%s\n' \
        "$DIM" date trigger status kept/seen items dur cost "$RESET"

    distill_run_all | jq -s -r --argjson n "$n" '
        sort_by(.t) | (if $n > 0 then .[-$n:] else . end) | .[]
        | [ ((.end // .t) | .[0:16] | sub("T"; " ")),
            (.trigger // "?"),
            .status,
            "\(.sessions.kept // 0)/\(.sessions.seen // 0)",
            ((.items // 0) | tostring),
            "\(.dur // 0)s",
            (.cost // 0) ] | @tsv' 2>/dev/null |
        while IFS=$'\t' read -r d tr st ks it du co; do
            if [ "$st" = "ok" ]; then
                printf '     %-16s  %-8s  %-6s  %9s  %5s  %6s  %7s\n' \
                    "$d" "$tr" "$st" "$ks" "$it" "$du" "$(printf '$%.2f' "$co")"
            else
                printf '     %-16s  %-8s  %s%-6s%s  %9s  %5s  %6s  %7s\n' \
                    "$d" "$tr" "$RED" "$st" "$RESET" "$ks" "$it" "$du" \
                    "$(printf '$%.2f' "$co")"
            fi
        done

    local total items cost
    rows="$(distill_run_all | jq -s -r --argjson n "$n" '
        (sort_by(.t) | (if $n > 0 then .[-$n:] else . end)) as $r
        | [ ($r | length),
            ([$r[].items] | add // 0),
            ([$r[].cost] | add // 0),
            ([$r[] | select(.status != "ok")] | length),
            ([$r[] | select((.sessions.seen // 0) > 0)] | length) ] | @tsv' 2>/dev/null)"
    IFS=$'\t' read -r total items cost failed quiet <<<"$rows"

    s_note "$(printf '%s run(s) · %s item(s) · $%.2f' \
        "${total:-0}" "${items:-0}" "${cost:-0}")"

    # The two shapes a table doesn't make obvious on its own.
    [ "${failed:-0}" -gt 0 ] &&
        s_fail "${failed} of the above failed — the reason is in the run record"
    if [ "${quiet:-0}" -eq 0 ] && [ "${total:-0}" -gt 0 ]; then
        s_warn "not one of these runs saw a single session — check: chez distill --status"
    fi
    return 0
}

# ─── Stats ────────────────────────────────────────────────────────────────────

# _distill_main_entries — how many rules are ACTUALLY in MAIN.md.
#
# Not the same as "eligible": distill_render_main stops selecting the moment the
# byte cap is reached, so an eligible entry can still be evicted. Counting the
# rendered file rather than trusting eligibility is what keeps --stats honest.
# Only the generated section is counted — Pinned.md bullets sit above it.
_distill_main_entries() {
    local main
    main="$(distill_memory_dir)/MAIN.md"
    [ -f "$main" ] || {
        echo 0
        return 0
    }
    awk -v h="## $_DISTILL_MAIN_HEADING" \
        '$0 == h {seg=1; next} seg && /^- / {n++} END {print n+0}' "$main"
}

# distill_stats — the corpus, aggregated. Read-only, no API calls.
distill_stats() {
    local minhits cap main_bytes in_main eligible evicted line
    s_section "chezdistill stats"

    _distill_preflight_paths || {
        s_fail "paths    unusable"
        return 0
    }

    minhits="$(distill_cfg minHits 2)"
    cap="$(distill_cfg mainCapBytes 6144)"

    line="$(distill_derive | jq -s -r 'if length == 0 then "" else
        "\(length) entr\(if length == 1 then "y" else "ies" end) from \([.[].hits] | add) sighting(s), \([.[].first_seen] | min) → \([.[].last_seen] | max)"
        end' 2>/dev/null)"
    if [ -z "$line" ]; then
        s_note "corpus   nothing extracted yet — nothing to report on"
        return 0
    fi
    s_pass "corpus   $line"

    in_main="$(_distill_main_entries)"
    main_bytes=0
    [ -f "$(distill_memory_dir)/MAIN.md" ] &&
        main_bytes="$(wc -c <"$(distill_memory_dir)/MAIN.md" | tr -d ' ')"
    s_note "in MAIN  ${in_main} entr$([ "$in_main" = "1" ] && echo y || echo ies) · ${main_bytes}B of ${cap}B"

    eligible="$(distill_eligible | jq -s '[.[] | select(.eligible)] | length' 2>/dev/null || echo 0)"
    evicted=$((eligible - in_main))
    [ "$evicted" -gt 0 ] &&
        s_warn "evicted  ${evicted} eligible entr$([ "$evicted" = "1" ] && echo y || echo ies) did not fit the cap — see Topics/"

    s_note "$(distill_eligible | jq -s -r --argjson m "$minhits" \
        '"waiting  \([.[] | select(.hits < $m)] | length) below the gate (< \($m) hits) · " +
         "\([.[] | select(.hits >= $m and (.eligible | not))] | length) stale"' 2>/dev/null)"

    s_note "$(distill_derive | jq -s -r '
        "topics   " + (if length == 0 then "none" else
        (group_by(.topic) | sort_by(-length) | .[0:5]
         | map("\(.[0].topic) \(length)") | join(" · "))
        + (if (group_by(.topic) | length) > 5
           then " · (+\((group_by(.topic) | length) - 5) more)" else "" end)
        end)' 2>/dev/null)"

    # `// "unknown"` because distill_derive takes .kind straight from the
    # extract with no fallback (unlike .topic), so an extract written before the
    # schema settled groups under a literal null.
    s_note "$(distill_derive | jq -s -r '
        "kinds    " + (if length == 0 then "none" else
        (group_by(.kind // "unknown") | sort_by(-length)
         | map("\(.[0].kind // "unknown") \(length)") | join(" · ")) end)' 2>/dev/null)"

    s_note "$(distill_derive | jq -s -r '
        "hits     " + (if length == 0 then "none" else
        ([.[] | if .hits >= 4 then "4+" else (.hits | tostring) end]
         | group_by(.) | sort_by(.[0]) | map("\(.[0])× \(length)") | join(" · ")) end)' 2>/dev/null)"

    s_note "$(printf 'spend    $%s over 7d · $%s over 30d' \
        "$(distill_spend_since 7 | jq -r '. * 100 | round / 100')" \
        "$(distill_spend_since 30 | jq -r '. * 100 | round / 100')")"

    line="$(distill_run_all | jq -s -r --arg since "$(distill_iso_ago 7)" '
        [.[] | select(.t > $since)] as $r
        | if ($r | length) == 0 then "runs     none in the last 7 days"
          else "runs     \($r | length) in 7d · \([$r[] | select(.status != "ok")] | length) failed · " +
               "\((([$r[].sessions.kept // 0] | add // 0) * 10 / ($r | length) | round) / 10) session(s) kept per run"
          end' 2>/dev/null)"
    s_note "${line:-runs     none recorded}"
    return 0
}
