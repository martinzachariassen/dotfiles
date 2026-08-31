#!/usr/bin/env bash
# --status and --logs.
#
# The read-only answers. No API calls, nothing written.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Status ───────────────────────────────────────────────────────────────────

# distill_status_sources — one line per configured transcript root, plus how many
# of them the next run would actually open. The window figure comes from
# distill_session_files and the cursor, so it is the real answer rather than a
# second implementation that could drift from the harvester.
distill_status_sources() {
    local root n total=0 configured=0 window
    # A configured root that does not exist is reported dim, not red. The list is
    # a set of candidates for where Claude Code keeps transcripts and only one is
    # ever real, so a red tick here would be permanent — and a check that is
    # always failing is a check nobody reads. Red is reserved for the state that
    # actually breaks a run: nothing readable anywhere.
    while IFS= read -r root; do
        [ -n "$root" ] || continue
        configured=$((configured + 1))
        if [ ! -d "$root" ]; then
            dim "         $(distill_tilde "$root") — not present on this Mac"
            continue
        fi
        n="$(distill_source_count "$root")"
        total=$((total + n))
        if [ "$n" -gt 0 ]; then
            s_pass "sources  $(distill_tilde "$root") — $n transcript(s)"
        else
            dim "         $(distill_tilde "$root") — present but empty"
        fi
    done < <(distill_source_roots)

    if [ "$configured" -eq 0 ]; then
        s_warn "sources  no transcriptRoots configured — nothing will be harvested"
        return 0
    fi
    if [ "$total" -eq 0 ]; then
        s_fail "sources  nothing to read — a run would fail rather than report ok"
        return 0
    fi
    window="$(distill_session_files "$(distill_cursor_read)" 2>/dev/null | wc -l | tr -d ' ')"
    s_note "         ${window:-0} in the window the next run would read"
}

distill_status() {
    local main cap spent ceiling n last line f url verdict va vb seed
    s_section "chezdistill"

    # Paths only. A remote conflict is reported below as its own line rather than
    # cutting the report short — it is the thing you opened --status to see.
    if ! _distill_preflight_paths; then
        s_fail "paths    unusable"
        return 0
    fi

    s_pass "memory   $(distill_memory_dir)"
    s_pass "state    $(distill_state_dir)"

    # The scope, unconditionally. `chez doctor` tells you to look here when the
    # stamp and this Mac disagree, and until now the report it pointed at did not
    # mention the scope at all. Printing it even when it agrees is what makes the
    # third state — no scope, so the leak boundary is abstaining — visible; that
    # one fails silently by construction and has nothing else to surface it.
    local mine theirs
    mine="$(distill_scope)"
    theirs="$(distill_corpus_scope)"
    if [ -z "$mine" ]; then
        s_fail "scope    not set — the corpus leak boundary is not being enforced"
        s_note "         set one with \`chez setup\`"
    elif [ -n "$theirs" ] && [ "$mine" != "$theirs" ]; then
        s_fail "scope    this Mac is \"$mine\", the corpus is stamped \"$theirs\""
        s_note "         chez distill --remote <$mine corpus url>, or --remote none"
    elif [ -z "$theirs" ]; then
        s_warn "scope    $mine — the corpus carries no stamp yet"
    else
        s_pass "scope    $mine"
    fi

    # The inputs, reported as plainly as the outputs. Without this line a machine
    # reading nothing at all looks exactly like a machine having a quiet week.
    distill_status_sources

    main="$(distill_memory_dir)/MAIN.md"
    cap="$(distill_cfg mainCapBytes 6144)"
    if [ -f "$main" ]; then
        n="$(wc -c <"$main" | tr -d ' ')"
        if [ "$n" -le "$cap" ]; then
            s_pass "MAIN.md  ${n}B of ${cap}B"
        else
            s_warn "MAIN.md  ${n}B, over the ${cap}B cap"
        fi
    else
        s_note "MAIN.md  not rendered yet"
    fi

    n="$(distill_derive | jq -s 'length' 2>/dev/null || echo 0)"
    line="$(distill_derive | jq -s -r 'if length == 0 then "" else
        "\([.[].hits] | add) sighting(s) of \(length) entr\(if length == 1 then "y" else "ies" end), oldest \([.[].first_seen] | min)"
        end' 2>/dev/null || true)"
    s_note "corpus   ${line:-nothing extracted yet}"

    n="$(distill_eligible | jq -s '[.[] | select(.eligible | not)] | length' 2>/dev/null || echo 0)"
    if [ "${n:-0}" -gt 0 ]; then
        s_note "waiting  ${n} entries below the gate or stale — see Candidates.md"
    fi

    # What the remote actually has, not what it is called. This line used to print
    # the origin URL and call that a pass, so a push that had been failing for two
    # days still rendered a green tick — see distill_backup_state.
    n="$(git -C "$(distill_state_dir)" rev-list --count HEAD 2>/dev/null || echo 0)"
    url="$(git -C "$(distill_state_dir)" remote get-url origin 2>/dev/null || true)"
    read -r verdict va vb <<<"$(distill_backup_state)"
    case "$verdict" in
        no-repo) s_note "backup   no state repo yet — the first run creates it" ;;
        no-remote) s_warn "backup   $n commit(s), local only — this Mac is the only copy" ;;
        wedged)
            s_fail "backup   the corpus repo is stuck mid-operation — nothing is being pushed"
            s_note "         git -C $(distill_state_dir) status"
            ;;
        no-upstream) s_fail "backup   $n commit(s), never pushed to $url" ;;
        ahead) s_warn "backup   $va commit(s) not yet on $url — the push is not getting through" ;;
        behind) s_warn "backup   $va commit(s) behind $url — the next run catches up" ;;
        diverged) s_fail "backup   diverged from $url — $va unpushed, $vb unpulled" ;;
        *) s_pass "backup   $n commit(s), pushed to $url" ;;
    esac
    # The seed is only ever consulted for a repo with no origin, so an answer
    # given on an already-attached Mac would otherwise vanish without a word.
    if seed="$(distill_remote_drift)"; then
        s_note "         setup names $seed — attach it with: chez distill --remote $seed"
    fi

    # Rounded for display. The raw sum is a float accumulated from per-call
    # costs, so it reads as $2.7951789000000002.
    spent="$(distill_spend_7d | jq -r '. * 100 | round / 100')"
    ceiling="$(distill_cfg maxSpendUsd7d 15.0)"
    s_note "spend    \$$spent of \$$ceiling over 7 days"

    last="$(distill_last_run)"
    if [ -z "$last" ]; then
        s_note "last run no run recorded yet"
    else
        line="$(printf '%s' "$last" | jq -r \
            '"\(.end[0:16] | sub("T"; " ")) UTC · \(.status)"
             + " · \(.sessions.kept)/\(.sessions.seen) session(s) · \(.dur // 0)s · $\(.cost * 100 | round / 100)"')"
        case "$(printf '%s' "$last" | jq -r '.status')" in
            ok) s_pass "last run $line" ;;
            *) s_fail "last run $line" ;;
        esac
        # Per-session reasons. "7 seen, 0 kept" reads as a broken job until you
        # can see that six were under minTurns and one had nothing durable in it,
        # and with the reports gone this is the only place that says so.
        while IFS= read -r line; do
            [ -n "$line" ] && dim "           $line"
        done < <(distill_run_last_detail)
    fi

    f="$(distill_cursor_file)"
    [ -f "$f" ] && s_note "cursor   read up to $(jq -r '.cursor // "?"' "$f")"
    return 0
}

# ─── Logs ─────────────────────────────────────────────────────────────────────

# distill_logs [N] [FOLLOW] — the tail of the nightly log.
#
# The path was only ever written down in a troubleshooting table, which means it
# was only reachable by someone who already suspected something was wrong. It is
# read-only, so it does not go through the `run` wrapper — same as --status.
distill_logs() {
    local n="${1:-50}" follow="${2:-0}" f
    f="$(distill_log_file)"
    s_section "chezdistill logs"

    if [ ! -f "$f" ]; then
        s_note "no log yet at $(distill_tilde "$f")"
        explain "launchd writes it on the first nightly run. Run one now: chezdistill"
        return 0
    fi
    if [ ! -s "$f" ]; then
        s_note "$(distill_tilde "$f") is empty"
        return 0
    fi

    s_note "$(distill_tilde "$f") · last $n line(s)"
    hr
    tail -n "$n" "$f"

    if [ "$follow" = "1" ]; then
        if [ "${DRY_RUN:-0}" = "1" ]; then
            dim "dry-run \$ tail -f $f"
            return 0
        fi
        hr
        s_note "following — ^C to stop"
        tail -f -n 0 "$f"
    fi
    return 0
}
