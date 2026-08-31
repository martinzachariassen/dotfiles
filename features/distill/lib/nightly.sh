#!/usr/bin/env bash
# The nightly run itself.
#
# What launchd invokes at 01:00, composed from every module above.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Nightly ──────────────────────────────────────────────────────────────────

# distill_run_daily — the nightly job, wrapped in a run record. The wrapper is
# what makes a failure visible: whatever the body does, distill_run_end still
# writes the record and is the one place that commits.
distill_run_daily() {
    local rc
    distill_run_begin
    _distill_daily_body
    rc=$?
    distill_run_end "$rc" || rc=1
    return "$rc"
}

_distill_daily_body() {
    local since now tmp sysfile schema filtered turns cwd out
    local sess name title mapped date n_items persisted=1 halted=0
    local n_called=0 n_failed=0 outage=0

    distill_spend_ok || return 1
    # Before the cursor, before the temp dir, before anything: a run with nowhere
    # to read from is a failure, not a quiet night. Going through distill_fail
    # puts the reason in the run record, so it reaches --status, --runs,
    # chezdoctor and the commit pushed to the corpus — rather than scrolling past
    # in a launchd log nobody opens.
    distill_sources_ok || return 1

    since="$(distill_cursor_read)"
    _DISTILL_RUN_SINCE="$since"
    now="$(distill_iso_now)"
    tmp="$(mktemp -d)"

    sysfile="$tmp/rubric.md"
    distill_rubric >"$sysfile"
    schema="$tmp/map.json"
    distill_schema_map >"$schema"

    info "reading transcripts since $since"

    while IFS= read -r sess; do
        [ -n "$sess" ] || continue
        name="$(basename "$sess" .jsonl)"
        DISTILL_RUN_SEEN=$((DISTILL_RUN_SEEN + 1))
        filtered="$tmp/$name.ndjson"
        distill_filter "$sess" "$since" | distill_dedupe >"$filtered"
        if [ ! -s "$filtered" ]; then
            distill_run_session "$name" 0 "nothing new since the cursor" 0
            continue
        fi

        turns="$(distill_turns <"$filtered")"
        cwd="$(jq -r 'select(.c != null) | .c' <"$filtered" | head -1)"
        title="$(distill_session_title "$sess")"
        date="$(jq -r '.t[0:10]' <"$filtered" | head -1)"

        if [ "${turns:-0}" -lt "$(distill_cfg minTurns 3)" ]; then
            dim "skip $name — only ${turns} typed turn(s)"
            distill_run_session "$name" "${turns:-0}" "too short, no model call" 0
            continue
        fi

        # Re-checked per session, not only in preflight. A nightly run reads two
        # days and cannot approach the ceiling, but `--since 90d` reads hundreds
        # of sessions in one go — and a ceiling checked once before any of them
        # is not a ceiling. Stop reading rather than fail: the sessions already
        # extracted are worth keeping, and the cursor stays where it was.
        if ! distill_spend_ok >/dev/null 2>&1; then
            distill_warn "7-day spend ceiling reached — stopping after $DISTILL_RUN_KEPT session(s)"
            distill_run_session "$name" "$turns" "spend ceiling reached" 0
            halted=1
            break
        fi

        n_called=$((n_called + 1))
        mapped="$(distill_claude "$(distill_cfg mapModel sonnet)" "$sysfile" "$schema" \
            "Session title: ${title:-untitled}. Extract durable items, or none." \
            <"$filtered")" || {
            n_failed=$((n_failed + 1))
            distill_run_session "$name" "$turns" "model call failed" 0
            continue
        }

        n_items="$(printf '%s' "$mapped" | jq -r '.items | length')"
        if [ "${n_items:-0}" = "0" ]; then
            dim "skip $name — nothing durable in it"
            distill_run_session "$name" "$turns" "nothing durable in it" 0
            continue
        fi

        printf '%s\n' "$mapped" |
            jq -c --arg s "$name" \
                --arg c "$cwd" --arg tool "${DISTILL_TOOL:-claude-code}" \
                '.items[] | . + {session:$s, cwd:$c, tool:$tool}' \
                >>"$tmp/items-$date.ndjson"
        DISTILL_RUN_KEPT=$((DISTILL_RUN_KEPT + 1))
        DISTILL_RUN_ITEMS=$((DISTILL_RUN_ITEMS + n_items))
        distill_run_session "$name" "$turns" "kept" "$n_items"
    done < <(distill_session_files "$since")

    ok "$DISTILL_RUN_KEPT of $DISTILL_RUN_SEEN session(s) yielded items"

    # Every call attempted, every one failed. That is not this window being
    # unlucky, it is the model being unreachable — no credentials under launchd,
    # no network, a bad model name. Individually a failure is forgiven (one poison
    # session must not wedge the cursor and re-bill forever), but "all of them"
    # means nothing about this window was actually tried, and advancing over it
    # would skip the sessions for good.
    if [ "$n_called" -gt 0 ] && [ "$n_failed" -eq "$n_called" ]; then
        outage=1
        distill_fail "every model call failed ($n_failed of $n_called) — treating this as an outage, not an empty night"
        explain \
            "The nightly job runs under launchd, which does not read your shell" \
            "config, so provider variables set in ~/.zshenv are absent there." \
            "Check the last error with: chezdistill --logs 40"
    elif [ "$n_failed" -gt 0 ]; then
        distill_warn "$n_failed of $n_called model call(s) failed — those sessions were skipped, not retried"
    fi

    # A dry run must not consume the very window it is previewing. Everything
    # above this point is read-only (distill_claude short-circuits under DRY_RUN);
    # everything below writes. Without this guard `chezdistill -n` advanced the
    # cursor and re-rendered the memory tier, so the "free preview" step in the
    # docs destroyed the window you were about to validate for real.
    if [ "${DRY_RUN:-0}" = "1" ]; then
        dim "dry-run — corpus, cursor and rendered memory left untouched"
        rm -rf "$tmp"
        return 0
    fi

    distill_persist_extracts "$tmp" || persisted=0

    distill_render_all
    distill_prune_extracts
    # The cursor only advances over a window that was read to the end. Stopping
    # early — a failed write, the spend ceiling, or a total model outage — must
    # hold it, or the sessions never reached are skipped for good and the gap is
    # invisible.
    if [ "$persisted" -eq 1 ] && [ "$halted" -eq 0 ] && [ "$outage" -eq 0 ]; then
        distill_cursor_write "$now"
    else
        distill_warn "cursor held at $since — the next run re-reads this window"
    fi
    rm -rf "$tmp"
    # An outage fails the run; the spend ceiling does not. Hitting the ceiling is
    # the brake working as designed and the sessions read before it are kept, so
    # that stays a warning — but it still holds the cursor, above.
    [ "$persisted" -eq 1 ] && [ "$outage" -eq 0 ]
}

# distill_persist_extracts TMPDIR — write this run's items into the corpus, one
# file per date and machine, merged with whatever this machine already wrote for
# that date. A backfill and a nightly run can both land on the same day, and
# `unique` keeps a session that was read twice from counting twice. Two Macs never
# touch each other's file, so a shared remote merges without a conflict; their
# overlap is settled at derive time, which counts distinct sessions.
#
# Appends each date it wrote to DISTILL_RUN_DATES. Returns non-zero if any write
# failed, which is the one failure in this job that loses money: the model calls
# are already billed by the time this runs, and no re-run recovers them. The
# caller holds the cursor back on non-zero so the next run reads the window again.
distill_persist_extracts() {
    local tmp="$1" f date out rc=0
    for f in "$tmp"/items-*.ndjson; do
        [ -f "$f" ] || continue
        date="$(basename "$f" .ndjson)"
        date="${date#items-}"
        out="$(distill_extract_file "$date")"
        mkdir -p "$(dirname "$out")" 2>/dev/null

        if [ -f "$out" ]; then
            # Through the same union an attach uses, so what a corpus contains is
            # decided in one place rather than by two jq expressions free to drift.
            if jq -s '{items: .}' "$f" >"$out.new" 2>/dev/null &&
                distill_extract_union "$out" "$out.new" "$out"; then
                rm -f "$out.new"
            else
                rm -f "$out.new" "$out.tmp"
                rc=1
            fi
        else
            jq -s '{items: .}' "$f" >"$out" 2>/dev/null || rc=1
        fi

        if [ "$rc" -ne 0 ]; then
            distill_fail "could not write $out — extracted items not saved"
            return 1
        fi
        DISTILL_RUN_DATES="$DISTILL_RUN_DATES $date"
    done
    return 0
}

# distill_guard_secrets — the sweep follows the content, not the directory. The
# extracts quote the conversation they came from, and MAIN.md is loaded into every
# session, so both are swept and any hit blocks every commit this run would have
# made.
distill_guard_secrets() {
    local d
    command -v gitleaks >/dev/null 2>&1 || {
        warn "gitleaks not installed — skipping the secret sweep"
        return 0
    }
    for d in "$(distill_state_dir)" "$(distill_memory_dir)"; do
        [ -n "$d" ] && [ -d "$d" ] || continue
        if ! gitleaks dir "$d" --redact --no-banner >/dev/null 2>&1; then
            fail "gitleaks found something in $d — not committing"
            return 1
        fi
    done
    return 0
}
