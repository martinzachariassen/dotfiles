#!/usr/bin/env bash
# What a run cost.
#
# The spend ledger: per-run token cost, appended, and the rolling window the
# budget gate reads.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Spend ────────────────────────────────────────────────────────────────────
#
# Append-only. The ceiling protects an account quota that `claude -p` shares with
# interactive work, so it is checked in preflight rather than after the fact.

distill_spend_file() {
    printf '%s/spend.jsonl\n' "$(distill_state_dir)"
}

distill_spend_record() {
    local usd="$1" f
    [ -n "$usd" ] || return 0
    case "$usd" in
        0 | 0.0 | null | '') return 0 ;;
    esac
    f="$(distill_spend_file)"
    mkdir -p "$(dirname "$f")"
    printf '{"t":"%s","usd":%s}\n' "$(distill_iso_now)" "$usd" >>"$f"
}

# distill_spend_since DAYS — total spend over a trailing window.
#
# Read as RAW lines and `fromjson?` each one, not `jq -s` over the file. This is
# an append-only log written by a job that can be killed mid-write, so a torn
# final line is an ordinary event, not a corruption scare. Slurping makes ONE bad
# line abort the whole parse, and the total then comes back 0 — which the ceiling
# below reads as "spent nothing, go ahead". A cost brake that fails open on the
# most likely form of damage is not a brake. Per-line, a torn record costs you
# that record's dollars and nothing else.
distill_spend_since() {
    local since f total
    since="$(distill_iso_ago "$1")"
    f="$(distill_spend_file)"
    [ -f "$f" ] || {
        echo 0
        return 0
    }
    total="$(jq -R -s --arg since "$since" '
        [ split("\n")[]
          | select(length > 0)
          | (fromjson? // empty)
          | select(.t > $since)
          | (.usd // 0) ]
        | add // 0' "$f" 2>/dev/null)"
    case "$total" in
        '' | null) echo 0 ;;
        *) printf '%s\n' "$total" ;;
    esac
}

# distill_spend_7d — the window the rolling ceiling is defined over. Named
# separately because it is a policy, not just a report: maxSpendUsd7d means this.
distill_spend_7d() {
    distill_spend_since 7
}

# distill_spend_ok — the rolling ceiling, checked in preflight so a runaway
# cannot quietly bill for a week before anyone notices.
distill_spend_ok() {
    local spent ceiling verdict
    spent="$(distill_spend_7d)"
    ceiling="$(distill_cfg maxSpendUsd7d 15.0)"

    # Fail CLOSED. The old form asked jq one question — `$s >= $c` — and read a
    # non-zero exit as "under the ceiling". But jq also exits non-zero when
    # --argjson is handed something that is not JSON, which is what an unreadable
    # spend file or a missing config key produces. The one condition that must
    # never be silently satisfied was satisfied by every error. Ask for the answer
    # as a VALUE instead, and treat "no answer" as a refusal.
    verdict="$(jq -n --argjson s "${spent:-null}" --argjson c "${ceiling:-null}" \
        'if ($s|type) == "number" and ($c|type) == "number"
         then (if $s >= $c then "over" else "under" end)
         else "unknown" end' 2>/dev/null | tr -d '"')"

    case "$verdict" in
        under) return 0 ;;
        over)
            distill_fail "7-day spend \$$spent has reached the \$$ceiling ceiling — refusing to start"
            return 1
            ;;
        *)
            distill_fail "could not evaluate the spend ceiling (spent='$spent', ceiling='$ceiling') — refusing to start"
            explain \
                "The rolling cost brake could not be read, so nothing is stopping a" \
                "runaway. Check maxSpendUsd7d in src/.chezmoidata/distill.toml and" \
                "~/.local/state/chezdistill/spend.jsonl, then: chezdistill --status"
            return 1
            ;;
    esac
}
