#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_distill() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# Gated on claudeDistiller by the registry.

doctor_distill() {
    # chezdistill has no human-facing output by design — the reports it used to write
    # into an Obsidian vault were removed. That took away the one passive signal that
    # the nightly job was still alive: if the launchd agent is gone, or the Mac was
    # off for a fortnight, MAIN.md simply stops growing and nothing says so. This
    # section is that signal. `chez distill --status` has the detail; this answers only
    # "is it still running", which is the question you never think to ask.
    section "Claude memory (claudeDistiller)"
    if ! command -v distill_last_run >/dev/null 2>&1; then
        warn "features/distill/lib.sh missing — chezdistill checks skipped"
    else
        if [ "$(uname -s)" = "Darwin" ]; then
            if launchctl print "gui/$(id -u)/no.mlz.chezdistill.nightly" >/dev/null 2>&1; then
                pass "nightly agent registered (01:00)"
            else
                fail "nightly agent not registered — nothing distils. Run: chez distill --setup"
            fi
        fi

        # Are there any inputs? Every other check here is on the output side, and
        # that is how a job whose transcriptRoots pointed at a directory that has
        # never existed passed this whole section, green, every day of its life:
        # registered, ran, wrote a MAIN.md, backed the corpus up — and read
        # nothing. "Could it have worked" is not "did it work".
        distill_sources=0
        while IFS= read -r distill_root; do
            [ -n "$distill_root" ] || continue
            distill_sources=$((distill_sources + $(distill_source_count "$distill_root")))
        done < <(distill_source_roots 2>/dev/null)
        if [ "$distill_sources" -eq 0 ]; then
            fail "no transcripts under any transcriptRoot — nothing can be distilled. See: chez distill --status"
        else
            pass "$distill_sources transcript(s) to read from"
        fi

        distill_last="$(distill_last_run 2>/dev/null || true)"
        if [ -z "$distill_last" ]; then
            note "no run recorded yet — backfill with: chez distill --since 7d"
        else
            distill_when="$(printf '%s' "$distill_last" | jq -r '.end // .t' 2>/dev/null)"
            distill_age="$(distill_days_since "$distill_when" 2>/dev/null || echo 0)"
            distill_verdict="$(printf '%s' "$distill_last" | jq -r '.status' 2>/dev/null)"
            if [ "$distill_verdict" != "ok" ]; then
                fail "last run failed ($(printf '%s' "$distill_when" | cut -c1-10)) — see: chez distill --status"
            elif [ "${distill_age:-0}" -gt 3 ]; then
                warn "last run was ${distill_age} days ago — the timer may not be firing. See: chez distill --status"
            else
                pass "last run ${distill_age} day(s) ago, ok"
            fi
            # Succeeded, and opened nothing, while transcripts sit there unread.
            # The exact shape of the transcriptRoots bug, and of the next thing
            # that quietly stops the harvester reaching the files.
            if [ "$distill_verdict" = "ok" ] && [ "$distill_sources" -gt 0 ] &&
                [ "$(printf '%s' "$distill_last" | jq -r '.sessions.seen // 0')" = "0" ]; then
                warn "the last run read 0 of $distill_sources transcript(s) — see: chez distill --runs"
            fi
        fi

        distill_main="$(distill_memory_dir)/MAIN.md"
        if [ -f "$distill_main" ]; then
            pass "MAIN.md present: $(wc -c <"$distill_main" | tr -d ' ')B of $(distill_cfg mainCapBytes 6144)B"
        else
            warn "MAIN.md not rendered — the persona imports nothing. Run: chez distill --render"
        fi

        # A corpus with no remote is one disk failure from gone, and it is the
        # only thing here that cannot be regenerated. Worse than no remote is the
        # other scope's remote: it looks like a backup, and it isn't — it is
        # one scope's memory promoted into another's sessions, one push past
        # undoing.
        # Whether it is REACHING the remote, not merely which remote it names.
        # This line used to pass on the strength of an origin URL existing, so a
        # push that had been rejected every night for two days still read green.
        # The verdict is computed once, in distill_backup_state, and only
        # rendered here — chez distill --status renders the same one.
        if ! distill_corpus_check_local >/dev/null 2>&1; then
            fail "the corpus is stamped $(distill_corpus_scope) but this is a $(distill_scope) Mac. See: chez distill --status"
        else
            distill_url="$(git -C "$(distill_state_dir)" remote get-url origin 2>/dev/null || true)"
            read -r distill_bv distill_bn _ <<<"$(distill_backup_state 2>/dev/null)"
            case "$distill_bv" in
                no-repo) note "no corpus repo yet — the first run creates it" ;;
                no-remote) warn "corpus is local only — this Mac is the only copy. Attach one: chez distill --remote <url>" ;;
                wedged) fail "the corpus repo is stuck mid-operation — nothing is being pushed. See: chez distill --status" ;;
                no-upstream) fail "corpus has never reached $distill_url. See: chez distill --status" ;;
                ahead) warn "$distill_bn corpus commit(s) not yet on $distill_url. See: chez distill --status" ;;
                behind) warn "corpus is $distill_bn commit(s) behind $distill_url — the next run catches up" ;;
                diverged) fail "corpus has diverged from $distill_url. See: chez distill --status" ;;
                *) pass "corpus backed up to $distill_url" ;;
            esac
        fi
    fi
}
