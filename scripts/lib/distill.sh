#!/usr/bin/env bash
# distill.sh — the chezdistill engine: harvest Claude Code transcripts and render
# the memory tier Claude loads.
#
# Two destinations, because the two have nothing in common:
#   DISTILL_MEMORY  ~/.config/claude/memory — MAIN.md, Topics/, Candidates.md.
#                   Read by Claude, and by nothing else.
#   DISTILL_STATE   ~/.local/state/chezdistill — the extract corpus, Pinned.md,
#                   cursor, spend, run log. The extracts ARE the memory: every
#                   rule, hit count and date is derived from them on each render.
#
# Design principle: the model extracts, bash decides and writes. Every judgement —
# hit counts, what earns a place in MAIN, what gets demoted — is computed here
# from the extract corpus, so a re-run of a day already distilled is a no-op. No
# model invocation in this file has write access.
# shellcheck disable=SC2034,SC2329

[ -n "${__DOTFILES_DISTILL_SH:-}" ] && return 0
__DOTFILES_DISTILL_SH=1

# ─── Config ───────────────────────────────────────────────────────────────────

_DISTILL_CFG=""
_DISTILL_DATA=""
_DISTILL_PROFILE=""

# _distill_data — all of `chezmoi data`, fetched once. Two callers want different
# parts of it (`.distill` and `.profile`) and it costs a subprocess each time.
_distill_data() {
    if [ -z "$_DISTILL_DATA" ]; then
        _DISTILL_DATA="$(chezmoi data --format=json 2>/dev/null)"
        [ -n "$_DISTILL_DATA" ] || _DISTILL_DATA='{}'
    fi
    printf '%s\n' "$_DISTILL_DATA"
}

# distill_config_ok — did the config actually load, or is `{}` standing in?
#
# `{}` is indistinguishable from a real config at every call site: every
# distill_cfg falls back to its built-in default, transcriptRoots comes back
# empty (so distill_sources_ok reads it as the deliberate harvest-nothing), and
# remotes comes back empty (so the foreign-corpus hard stop cannot fire). One
# unreadable file therefore disarms both input guards and every threshold at
# once, quietly — chezmoi off PATH, a moved checkout, or a syntax error in any
# .chezmoidata file is enough. "No config" and "a config that says nothing" are
# different facts, exactly like "no transcripts" and "a quiet night".
distill_config_ok() {
    [ -n "${DISTILL_CONFIG_JSON:-}" ] && return 0
    [ "$(distill_config)" != "{}" ] && return 0
    distill_fail "could not read the distill config — every limit and guard is at its default"
    explain \
        "\`chezmoi data\` returned nothing usable. Check that chezmoi is on PATH," \
        "that the checkout is where chezmoi expects, and that the files in" \
        "src/.chezmoidata/ parse: bash scripts/ci/lint-config.sh \"\$PWD\""
    return 1
}

# distill_config — the `.distill` table from .chezmoidata, fetched once.
distill_config() {
    if [ -z "$_DISTILL_CFG" ]; then
        if [ -n "${DISTILL_CONFIG_JSON:-}" ]; then
            _DISTILL_CFG="$DISTILL_CONFIG_JSON"
        else
            _DISTILL_CFG="$(_distill_data | jq -c '.distill // {}' 2>/dev/null)"
        fi
        [ -n "$_DISTILL_CFG" ] || _DISTILL_CFG='{}'
    fi
    printf '%s\n' "$_DISTILL_CFG"
}

# distill_profile — which profile this Mac was set up as: "personal" or "work".
#
# The only thing in this file that reads outside the `.distill` table, and it
# earns it: the corpus a machine pushes to is a property of the machine, not of
# the config. Empty when chezmoi is not on PATH, which every caller treats as
# "no opinion" rather than as an error.
distill_profile() {
    if [ -z "$_DISTILL_PROFILE" ]; then
        if [ -n "${DISTILL_PROFILE:-}" ]; then
            _DISTILL_PROFILE="$DISTILL_PROFILE"
        else
            _DISTILL_PROFILE="$(_distill_data | jq -r '.profile // empty' 2>/dev/null)"
        fi
    fi
    printf '%s\n' "$_DISTILL_PROFILE"
}

# distill_cfg KEY [DEFAULT] — one scalar.
distill_cfg() {
    local key="$1" fallback="${2:-}" out
    out="$(distill_config | jq -r --arg k "$key" '.[$k] // empty')"
    [ -n "$out" ] && printf '%s\n' "$out" || printf '%s\n' "$fallback"
}

# distill_cfg_list KEY — one array, newline separated, empty when absent.
distill_cfg_list() {
    distill_config | jq -r --arg k "$1" '(.[$k] // [])[]'
}

# distill_expand PATH — leading ~ only; config paths are ours, not user input.
distill_expand() {
    case "$1" in
        "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
        "~") printf '%s\n' "$HOME" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# ─── Portable date helpers (BSD on macOS, GNU in CI) ──────────────────────────

# distill_iso_ago DAYS — ISO-8601 Z timestamp DAYS in the past.
distill_iso_ago() {
    date -u -v-"$1"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
        date -u -d "$1 days ago" +%Y-%m-%dT%H:%M:%SZ
}

distill_iso_now() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# distill_iso_epoch ISO — seconds since epoch, 0 when unparseable.
distill_iso_epoch() {
    date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null ||
        date -u -d "$1" +%s 2>/dev/null ||
        echo 0
}

# distill_days_since ISO — whole days between ISO and now.
distill_days_since() {
    local then now
    then="$(distill_iso_epoch "$1")"
    now="$(date -u +%s)"
    [ "$then" -gt 0 ] 2>/dev/null || {
        echo 9999
        return 0
    }
    echo $(((now - then) / 86400))
}

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
    distill_remote_check || return 1
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

# ─── Model invocation ─────────────────────────────────────────────────────────
#
# Every call here is toolless and writes nothing. The rubric REPLACES the default
# system prompt rather than appending to it: this is a pure extraction task with
# no need for Claude Code's persona or tool guidance, and measured on this install
# it cuts the per-call cost by roughly an order of magnitude ($0.063 → $0.004,
# most of the difference being harness context that is cached and re-read).

# distill_claude MODEL SYSTEM_FILE SCHEMA_FILE PROMPT — payload on stdin.
# Prints the validated structured output; returns 1 on any failure.
distill_claude() {
    local model="$1" sysfile="$2" schemafile="$3" prompt="$4"
    local budget envelope err

    budget="$(distill_cfg maxBudgetUsd 2.0)"

    if [ "${DRY_RUN:-0}" = "1" ]; then
        # To stderr, not stdout: the caller captures this function's stdout as the
        # model's answer, so the notice would be parsed as part of the JSON. It
        # was — `jq: parse error at line 1, column 10` is the width of "dry-run $ "
        # — and every session in a dry run therefore reported "nothing durable".
        dim "dry-run \$ claude -p --model $model --tools \"\" (payload on stdin)" >&2
        echo '{}'
        return 0
    fi

    # stderr to its own file, NOT folded into the capture with 2>&1. Merging them
    # means any chatter on an otherwise successful call — an update notice, a
    # plugin sync, a node deprecation warning — lands in front of the JSON and
    # makes `jq -e .` reject it. That call is already billed at that point, so the
    # merge converts "we paid and got an answer" into "we paid and dropped it",
    # and the diagnostic prints the notice instead of the problem.
    local errfile
    errfile="$(mktemp)"
    envelope="$(claude -p \
        --model "$model" \
        --no-session-persistence \
        --tools "" \
        --system-prompt-file "$sysfile" \
        --json-schema "$(cat "$schemafile")" \
        --max-budget-usd "$budget" \
        --output-format json \
        "$prompt" 2>"$errfile")" || {
        distill_fail "claude invocation failed for model $model"
        [ -s "$errfile" ] && head -3 "$errfile" >&2
        rm -f "$errfile"
        return 1
    }

    if ! printf '%s' "$envelope" | jq -e . >/dev/null 2>&1; then
        # Loud, because this is the one branch that can burn money and keep
        # nothing: claude exited 0, so the call was made and billed, but the
        # answer is unusable and no cost line gets written either.
        distill_fail "claude exited 0 but returned non-JSON — the call was billed and the result is lost"
        printf '%s\n' "$envelope" | head -3 >&2
        [ -s "$errfile" ] && head -3 "$errfile" >&2
        rm -f "$errfile"
        return 1
    fi
    rm -f "$errfile"

    distill_spend_record "$(printf '%s' "$envelope" | jq -r '.total_cost_usd // 0')"

    if [ "$(printf '%s' "$envelope" | jq -r '.is_error // false')" = "true" ]; then
        err="$(printf '%s' "$envelope" | jq -r '.result // .subtype // "unknown"')"
        distill_fail "claude reported an error: $err"
        return 1
    fi

    printf '%s' "$envelope" | jq -e '.structured_output' 2>/dev/null || {
        distill_fail "claude returned no structured output"
        return 1
    }
}

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

# ─── Run log ──────────────────────────────────────────────────────────────────
#
# One record per run, appended to runs.jsonl and read back by `--status`. The
# point is the runs nobody watches: a nightly job that skipped every session at
# 01:00 otherwise leaves its only trace in a launchd log, and "nothing ran" and
# "nothing was worth keeping" have to stay distinguishable.
#
# The record is written even when the run failed. The commit may not happen (a
# gitleaks hit blocks it), but the file is append-only, so the next run that does
# commit carries the failed run's record with it.

distill_run_file() {
    printf '%s/runs.jsonl\n' "$(distill_state_dir)"
}

# distill_log_file — where launchd sends the nightly job's stdout AND stderr
# (both keys in the plist point here). Gitignored: it describes one machine's
# 01:00, and two Macs appending to one file would conflict on every line.
distill_log_file() {
    printf '%s/logs/nightly.log\n' "$(distill_state_dir)"
}

# distill_run_all — every record, oldest first.
distill_run_all() {
    cat "$(distill_run_file)" 2>/dev/null
}

# distill_run_begin — open the record for this run.
distill_run_begin() {
    _DISTILL_RUN_START="$(distill_iso_now)"
    _DISTILL_RUN_EPOCH="$(date -u +%s)"
    _DISTILL_RUN_SINCE=""
    _DISTILL_EVENTS="$(mktemp)"
    _DISTILL_SESSIONS="$(mktemp)"
    DISTILL_RUN_SEEN=0
    DISTILL_RUN_KEPT=0
    DISTILL_RUN_ITEMS=0
    DISTILL_RUN_DATES=""
}

# distill_event LEVEL TEXT — remember a line for the record. A no-op outside a
# run, so --status and --render can call the same helpers.
distill_event() {
    [ -f "${_DISTILL_EVENTS:-}" ] || return 0
    printf '%s\t%s\n' "$1" "$2" >>"$_DISTILL_EVENTS"
}

# distill_warn / distill_fail — say it on the console AND keep it in the run
# record. Nobody reads the launchd log of the Mac that was asleep.
distill_warn() {
    distill_event warn "$1"
    warn "$1"
}

distill_fail() {
    distill_event fail "$1"
    fail "$1"
}

# distill_run_session NAME TURNS VERDICT ITEMS — why one session was kept or
# skipped. This is what makes a quiet run legible: "7 seen, 0 kept" is alarming
# until you can see that six were under minTurns and cost nothing.
distill_run_session() {
    [ -f "${_DISTILL_SESSIONS:-}" ] || return 0
    jq -nc --arg s "$1" --argjson t "${2:-0}" \
        --arg v "$3" --argjson n "${4:-0}" \
        '{session:$s, turns:$t, verdict:$v, items:$n}' \
        >>"$_DISTILL_SESSIONS"
}

# distill_run_cost — what this run spent, read back from the same spend log the
# rolling ceiling uses rather than counted separately.
distill_run_cost() {
    local f
    f="$(distill_spend_file)"
    [ -f "$f" ] || {
        echo 0
        return 0
    }
    jq -s --arg since "${_DISTILL_RUN_START:-}" \
        '[.[] | select(.t >= $since) | .usd] | add // 0' "$f" 2>/dev/null || echo 0
}

# distill_run_record STATUS — append this run to this machine's log.
distill_run_record() {
    local status="$1" f notes sessions cost main
    f="$(distill_run_file)"
    mkdir -p "$(dirname "$f")"

    notes="$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")
                          | {level: .[0], text: (.[1] // "")})' \
        <"${_DISTILL_EVENTS:-/dev/null}" 2>/dev/null)"
    sessions="$(jq -s -c '.' <"${_DISTILL_SESSIONS:-/dev/null}" 2>/dev/null)"
    cost="$(distill_run_cost)"
    main=0
    [ -f "$(distill_memory_dir)/MAIN.md" ] &&
        main="$(wc -c <"$(distill_memory_dir)/MAIN.md" | tr -d ' ')"

    jq -nc \
        --arg t "${_DISTILL_RUN_START:-$(distill_iso_now)}" \
        --arg end "$(distill_iso_now)" \
        --argjson dur "$(($(date -u +%s) - ${_DISTILL_RUN_EPOCH:-0}))" \
        --arg trigger "${DISTILL_TRIGGER:-manual}" \
        --arg since "${_DISTILL_RUN_SINCE:-}" \
        --arg dates "${DISTILL_RUN_DATES:-}" \
        --argjson seen "${DISTILL_RUN_SEEN:-0}" \
        --argjson kept "${DISTILL_RUN_KEPT:-0}" \
        --argjson items "${DISTILL_RUN_ITEMS:-0}" \
        --argjson cost "${cost:-0}" \
        --argjson main "${main:-0}" \
        --arg status "$status" \
        --argjson notes "${notes:-[]}" \
        --argjson sessions "${sessions:-[]}" \
        '{t:$t, end:$end, dur:$dur, trigger:$trigger,
          since:$since, status:$status, items:$items, cost:$cost,
          main_bytes:$main,
          dates:($dates | split(" ") | map(select(length > 0))),
          sessions:{seen:$seen, kept:$kept, detail:$sessions},
          notes:$notes}' >>"$f"
}

# distill_run_prune — the log is a running record, not an archive.
distill_run_prune() {
    local f cutoff
    f="$(distill_run_file)"
    [ -f "$f" ] || return 0
    cutoff="$(distill_iso_ago "$(distill_cfg runRetentionDays 90)")"
    jq -c --arg c "$cutoff" 'select(.t >= $c)' "$f" >"$f.tmp" 2>/dev/null &&
        mv "$f.tmp" "$f" || rm -f "$f.tmp"
}

# distill_last_run — the newest record, one JSON line.
distill_last_run() {
    distill_run_all | jq -s -c 'sort_by(.t) | last // empty' 2>/dev/null
}

# distill_run_last_detail — the newest run, per session, as plain lines. What
# makes a quiet run legible: "7 seen, 0 kept" is alarming until you can see that
# six were under minTurns and one had nothing durable in it.
distill_run_last_detail() {
    distill_run_all | jq -s -r '
        (sort_by(.t) | last) as $r
        | if $r == null then empty
          else ($r.sessions.detail // [])[]
               | "\(.session[0:8])  \(.turns) turn(s) · \(.verdict)"
                 + (if .items > 0 then " · \(.items) item(s)" else "" end)
          end' 2>/dev/null
}

# distill_run_message STATUS — the commit subject for this run.
distill_run_message() {
    local dates="${DISTILL_RUN_DATES:-}"
    if [ "$1" != "ok" ]; then
        printf 'chore(distill): failed run\n'
    elif [ -n "${dates// /}" ]; then
        printf 'chore(distill): extracts for%s\n' "$dates"
    else
        printf 'chore(distill): run log\n'
    fi
}

# distill_run_end RC — close the record and publish. This is the ONLY place
# anything is committed: a run that failed half way still has to leave its record
# behind, and putting the record in the same commit as the extracts is what keeps
# the two from disagreeing about what happened.
distill_run_end() {
    local rc="$1" status="ok" msg

    [ "$rc" -eq 0 ] || status="failed"
    # A body can return 0 while individual writes failed underneath it — which is
    # exactly how a run where nothing reached disk was recorded as "ok". Any
    # fail-level event this run recorded overrides the body's own verdict.
    if [ -f "${_DISTILL_EVENTS:-}" ] &&
        grep -q '^fail	' "${_DISTILL_EVENTS}" 2>/dev/null; then
        status="failed"
    fi
    msg="$(distill_run_message "$status")"

    if [ "${DRY_RUN:-0}" != "1" ]; then
        distill_run_record "$status"
        distill_run_prune
    fi
    rm -f "${_DISTILL_EVENTS:-}" "${_DISTILL_SESSIONS:-}"
    _DISTILL_EVENTS=""
    _DISTILL_SESSIONS=""

    distill_guard_secrets || return 1
    distill_commit_local "$msg"
    return 0
}

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
            "for f in \$(chezdistill --status >/dev/null; echo ~/.local/state/chezdistill/extracts/*.json);" \
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

# ─── Git ──────────────────────────────────────────────────────────────────────
#
# One repo: the state dir. It exists so `--undo` still means something, since the
# memory tier is derived and can always be re-rendered from the corpus. Its
# remote comes from the profile, so the corpus survives the machine without
# anyone opting in. This path never touches the repo this script ships in.

# Never let the network block a headless job. Without these an unreachable remote
# makes git sit on an SSH or credential prompt forever, and a launchd job has no
# terminal to answer it — the run hangs until the machine is rebooted.
distill_git_env() {
    export GIT_TERMINAL_PROMPT=0
    export GIT_ASKPASS=/usr/bin/true
    export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
}

# distill_state_branch [OVERRIDE] — the branch this corpus lives on, named out
# loud.
#
# Nothing here used to name one, which worked only by luck. `git init` follows
# `init.defaultBranch`, so a Mac that sets it to `main` and a runner that sets
# nothing — and so gets `master` — disagree about what to fetch, check out and
# push, and the disagreement surfaces as a push that is rejected forever. Prefer
# what the remote already calls it, then what this repo is already on.
distill_state_branch() {
    local repo b="${1:-}"
    [ -n "$b" ] && {
        printf '%s\n' "$b"
        return 0
    }
    repo="$(distill_state_dir)"
    b="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)"
    [ -n "$b" ] || b="$(git -C "$repo" config --get init.defaultBranch 2>/dev/null)"
    printf '%s\n' "${b:-main}"
}

# distill_remote_probe URL — one network call, two answers: has this remote
# anything in it yet, and what does it call its default branch?
#
# Exit 1 means empty, unreachable or unreadable — every caller treats those the
# same way, because none of them can fetch in any of those cases. Exit 0 prints
# the branch name (possibly empty, if the remote publishes no symbolic HEAD).
distill_remote_probe() {
    local url="$1" out
    [ -n "$url" ] || return 1
    distill_git_env
    out="$(git ls-remote --symref "$url" HEAD 2>/dev/null)" || return 1
    [ -n "$out" ] || return 1
    printf '%s\n' "$out" |
        sed -n 's#^ref: refs/heads/\([^[:space:]]*\).*#\1#p' | head -n1
    return 0
}

# distill_state_wedged — is the corpus repo stuck mid-rebase or mid-merge?
#
# Left behind by the `push || pull --rebase || push` fallback this file used to
# use: when the rebase stopped, `.git/rebase-merge` stayed and HEAD was detached,
# so every later run committed onto a branch that no longer pointed anywhere and
# pushed nothing. It ran that way for two days on this machine, reporting a green
# tick throughout.
#
# Deliberately only detected, never repaired. `--abort` would restore the branch
# but overwrite the working copy of files an older layout tracked; `--quit` would
# keep the tree but drop whatever had not been replayed yet — and that can be
# corpus nobody else has. Both are judgement calls, so this says so and stops.
distill_state_wedged() {
    local repo gd
    repo="$(distill_state_dir)"
    gd="$(git -C "$repo" rev-parse --git-dir 2>/dev/null)" || return 1
    case "$gd" in /*) ;; *) gd="$repo/$gd" ;; esac

    if [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; then
        printf 'rebase\n'
        return 0
    fi
    [ -f "$gd/MERGE_HEAD" ] && {
        printf 'merge\n'
        return 0
    }
    [ -f "$gd/CHERRY_PICK_HEAD" ] && {
        printf 'cherry-pick\n'
        return 0
    }

    # The state the machine was actually found in: `rebase --quit` clears the
    # directory above but leaves HEAD detached, and a detached HEAD accepts
    # commits happily — they just belong to no branch and push nowhere. An
    # unborn branch is not detached, so check that HEAD resolves first.
    if git -C "$repo" rev-parse --quiet --verify HEAD >/dev/null 2>&1 &&
        ! git -C "$repo" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
        printf 'detached\n'
        return 0
    fi
    return 1
}

# distill_state_sync — reconcile with the remote, atomically or not at all.
#
# Merge, not rebase. Nobody reads this history — `--undo` walks back one commit
# and the memory tier is derived — so rebase buys nothing and has exactly one
# failure mode, the one above. A merge either succeeds or is undone whole by
# `--abort`. Extract shards are per-host, so in the ordinary two-Mac case the
# merge is a union of files that do not overlap.
distill_state_sync() {
    local repo branch wedge
    repo="$(distill_state_dir)"

    if wedge="$(distill_state_wedged)"; then
        distill_warn "the corpus repo is stuck mid-$wedge — not syncing until that is settled"
        return 1
    fi

    branch="$(distill_state_branch)"
    distill_git_env
    git -C "$repo" fetch --quiet origin "$branch" >/dev/null 2>&1 || return 1
    git -C "$repo" rev-parse --quiet --verify "origin/$branch" >/dev/null 2>&1 || return 0

    git -C "$repo" merge --quiet --ff-only "origin/$branch" >/dev/null 2>&1 && return 0

    if ! git -C "$repo" merge --quiet --no-edit "origin/$branch" >/dev/null 2>&1; then
        git -C "$repo" merge --abort >/dev/null 2>&1 || true
        distill_warn "the corpus and its remote have diverged in a way that needs a hand"
        return 1
    fi
    return 0
}

# distill_backup_state — is the corpus actually reaching its remote?
#
# The question `--status` never asked. It printed the remote's URL and called
# that a pass, so a push that had been failing for days still rendered as backed
# up. Read-only and offline — it compares what is committed against what was last
# known to be on the remote, so it is safe for `--status` and `chezdoctor`.
#
# Prints one verdict: no-repo · no-remote · wedged · no-upstream · synced ·
# ahead N · behind N · diverged N M.
distill_backup_state() {
    local repo branch counts ahead behind
    repo="$(distill_state_dir)"

    git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || {
        printf 'no-repo\n'
        return 0
    }
    [ -n "$(git -C "$repo" remote 2>/dev/null)" ] || {
        printf 'no-remote\n'
        return 0
    }
    distill_state_wedged >/dev/null && {
        printf 'wedged\n'
        return 0
    }

    branch="$(distill_state_branch)"
    counts="$(git -C "$repo" rev-list --left-right --count \
        "origin/$branch...HEAD" 2>/dev/null)" || {
        printf 'no-upstream\n'
        return 0
    }
    [ -n "$counts" ] || {
        printf 'no-upstream\n'
        return 0
    }

    behind="${counts%%[[:space:]]*}"
    ahead="${counts##*[[:space:]]}"
    if [ "${behind:-0}" -gt 0 ] && [ "${ahead:-0}" -gt 0 ]; then
        printf 'diverged %s %s\n' "$ahead" "$behind"
    elif [ "${ahead:-0}" -gt 0 ]; then
        printf 'ahead %s\n' "$ahead"
    elif [ "${behind:-0}" -gt 0 ]; then
        printf 'behind %s\n' "$behind"
    else
        printf 'synced\n'
    fi
    return 0
}

# distill_state_restore — put an existing corpus back on a machine that has none.
#
# The half that was only ever described. Its absence is why a rebuilt Mac never
# came back: `git init` starts an unrelated history, so the first push is rejected
# as non-fast-forward and so is every one after it, forever, while the corpus it
# was meant to inherit sits on the remote untouched.
#
# Fetch and check out rather than `git clone`, because by the time this runs the
# state dir is not empty — cursor.json, logs/ and today's extracts are already in
# it, and clone refuses a non-empty target.
#
# Only for a repo with no commits of its own. One that already has a history is
# reconciled by distill_state_sync; if that history is unrelated to the remote's
# there is no safe automatic answer, so it says so rather than picking one.
distill_state_restore() {
    local repo branch remote
    repo="$(distill_state_dir)"

    git -C "$repo" rev-parse --quiet --verify HEAD >/dev/null 2>&1 && return 0

    remote="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 0
    [ -n "$remote" ] || return 0

    branch="$(distill_remote_probe "$remote")" || return 0
    branch="$(distill_state_branch "$branch")"

    distill_git_env
    git -C "$repo" fetch --quiet origin "$branch" >/dev/null 2>&1 || return 0
    git -C "$repo" rev-parse --quiet --verify "origin/$branch" >/dev/null 2>&1 || return 0

    # Git refuses this rather than overwriting an untracked file that the remote
    # also has — a same-host, same-day rebuild is the only way that happens, and
    # refusing is the right answer: the local copy is this machine's own work.
    git -C "$repo" checkout -q -B "$branch" --track "origin/$branch" >/dev/null 2>&1 || {
        distill_warn "could not restore the corpus from $remote without overwriting local work"
        return 0
    }
    info "restored the corpus from $remote"
    return 0
}

# ─── Which corpus is this Mac's? ──────────────────────────────────────────────
#
# One remote per profile, from `[distill.remotes]` in .chezmoidata. Not one
# shared repo with a branch each: `hits` is counted over the whole corpus, so a
# work rule seen in two work sessions would be promoted into a personal Mac's
# MAIN.md the moment the two histories met. Two Macs on the SAME profile sharing
# a remote is the case this is built for — extracts are sharded per host.

# distill_remote_url [PROFILE] — the corpus this profile belongs to, or empty
# when the table has no entry for it (a third profile, or chezmoi unavailable).
distill_remote_url() {
    local p="${1:-$(distill_profile)}"
    [ -n "$p" ] || return 0
    distill_config | jq -r --arg p "$p" '(.remotes // {})[$p] // empty'
}

# distill_remote_id URL — host/owner/repo, lowercased.
#
# Comparing remote URLs as strings gets this wrong in the one direction that
# matters: `git@github.com:me/x.git` and `https://github.com/me/X` are the same
# repo, and a mismatch here would refuse to run on a machine that is set up
# correctly. Reduce both to the identity GitHub actually uses before comparing.
distill_remote_id() {
    local u="$1"
    u="${u%.git}"
    u="${u%/}"
    u="${u#https://}"
    u="${u#http://}"
    u="${u#ssh://}"
    u="${u#git://}"
    u="${u#*@}" # git@host, or a token baked into an https URL
    u="${u/://}"
    printf '%s\n' "$u" | tr '[:upper:]' '[:lower:]'
}

# distill_remote_adopt — give a remote-less state repo the origin its profile
# says it should have. Never overwrites: an origin that is already set was set by
# someone, and this is not the code to second-guess it.
distill_remote_adopt() {
    local repo url
    repo="$(distill_state_dir)"
    [ -z "$(git -C "$repo" remote 2>/dev/null)" ] || return 0
    url="$(distill_remote_url)"
    [ -n "$url" ] || return 0
    git -C "$repo" remote add origin "$url" >/dev/null 2>&1 || return 0
    info "corpus backup set to $url ($(distill_profile) profile)"
}

# distill_remote_conflict — true, printing the offending profile's name, when
# origin is demonstrably ANOTHER profile's corpus.
#
# This is the half that matters. Attaching a work Mac to the personal repo is a
# single successful-looking command; every check downstream then reports a green
# "corpus backed up" while work transcripts are distilled into personal memory,
# and no push can be taken back. Only a URL that appears in the table under a
# different key is an error — any other remote is someone's own mirror, and this
# has no business having an opinion about it.
distill_remote_conflict() {
    local repo cur want mine entry key
    repo="$(distill_state_dir)"
    cur="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 1
    [ -n "$cur" ] || return 1
    mine="$(distill_profile)"
    want="$(distill_remote_url "$mine")"
    [ -n "$want" ] || return 1
    [ "$(distill_remote_id "$cur")" = "$(distill_remote_id "$want")" ] && return 1

    while IFS=$'\t' read -r key entry; do
        [ -n "$key" ] || continue
        [ "$key" = "$mine" ] && continue
        [ "$(distill_remote_id "$cur")" = "$(distill_remote_id "$entry")" ] || continue
        printf '%s\n' "$key"
        return 0
    done < <(distill_config | jq -r '(.remotes // {}) | to_entries[] | "\(.key)\t\(.value)"')
    return 1
}

# distill_remote_check — the conflict rendered as a refusal. 1 = do not proceed.
distill_remote_check() {
    local foreign
    foreign="$(distill_remote_conflict)" || return 0
    fail "the corpus at $(distill_state_dir) pushes to the $foreign remote, but this is a $(distill_profile) Mac"
    info "nothing will be distilled until that is settled. To adopt this Mac's own corpus:"
    info "  git -C $(distill_state_dir) remote set-url origin $(distill_remote_url)"
    info "  git -C $(distill_state_dir) remote set-url --push origin $(distill_remote_url)"
    return 1
}

# distill_state_repo_pushurl — push this repo over the URL it was cloned from.
#
# A global `url.git@github.com:.pushinsteadof https://github.com/` rewrites every
# HTTPS push to SSH, and this machine's SSH key lives behind 1Password. At 01:00
# the Mac is asleep or locked, so the agent is locked, so the push fails and the
# corpus quietly stops leaving the machine until someone runs the job by hand —
# which is the opposite of what a backup is for.
#
# Pinning the push URL to the fetch URL opts this one repo out of that rewrite.
# It is set only when the remote is already HTTPS and no push URL was configured,
# so an SSH remote is left exactly as the user set it up.
distill_state_repo_pushurl() {
    local repo fetch
    repo="$(distill_state_dir)"
    fetch="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 0
    case "$fetch" in https://*) ;; *) return 0 ;; esac
    [ -z "$(git -C "$repo" config --get remote.origin.pushurl 2>/dev/null)" ] || return 0
    git -C "$repo" config remote.origin.pushurl "$fetch" >/dev/null 2>&1 || true
}

# distill_commit_local MESSAGE — commit the state dir, and push to the profile's
# corpus remote. The commit is what matters and it is made first, so the network
# can never cost you a night's work: a failed push is reported and retried by the
# next run, never treated as a failed run.
#
# Only state is tracked, not memory. MAIN.md, Topics/ and Candidates.md are a
# pure function of the extract corpus, so reverting the inputs and
# re-rendering puts the memory tier back exactly — which is what `--undo` does.
# Versioning derived output alongside its input would just be two copies of the
# same decision, free to disagree.
distill_commit_local() {
    local repo="" msg="$1" branch="" wedge=""
    repo="$(distill_state_dir)"
    [ "${DRY_RUN:-0}" = "1" ] && {
        dim "dry-run \$ git -C $repo commit -m '$msg'"
        return 0
    }
    [ -d "$repo" ] || return 0

    distill_state_repo_init || return 0

    # Before `add -A`, not after. A wedged repo takes commits without complaint —
    # onto a detached HEAD, or on top of a half-finished rebase — and that is
    # precisely how two days of nightly runs ended up on a branch that did not
    # exist. Leaving the work uncommitted on disk loses nothing: the corpus is
    # the files, and the next run commits them once the repo is untangled.
    if wedge="$(distill_state_wedged)"; then
        distill_warn "the corpus repo is stuck mid-$wedge — not committing onto it"
        info "settle it by hand, then the next run picks up where this one stopped:"
        info "  git -C $repo status"
        return 0
    fi

    git -C "$repo" add -A >/dev/null 2>&1 || true
    if ! git -C "$repo" diff --cached --quiet 2>/dev/null; then
        git -C "$repo" commit -q -m "$msg" >/dev/null 2>&1 || {
            distill_warn "could not commit the state repo"
            return 0
        }
    fi

    # Only if one was configured. Offline is not an error here either: the commit
    # is already made, and the next run carries it.
    [ -n "$(git -C "$repo" remote 2>/dev/null)" ] || return 0
    distill_git_env

    # -u every time, not just the first: a repo created by `git init` and pointed
    # at a remote by hand has no upstream at all, and without one `git push` has
    # nothing to push to and the old fallback's `pull --rebase` failed outright
    # with "no tracking information". That is the whole of why a rebuilt Mac never
    # re-attached to its corpus.
    branch="$(distill_state_branch)"
    git -C "$repo" push -q -u origin "$branch" >/dev/null 2>&1 && return 0

    # Rejected almost always means the other Mac pushed first. Reconcile and retry
    # once; anything left after that is for a human, not for 01:00.
    distill_state_sync || {
        info "state push deferred — the next run will carry it"
        return 0
    }
    git -C "$repo" push -q -u origin "$branch" >/dev/null 2>&1 ||
        info "state push deferred — the next run will carry it"
    return 0
}

# distill_render_state_readme — the repo explaining itself, on GitHub.
#
# This one is not for you and not for Claude: it is for whoever opens the remote
# on a machine that has none of this set up, which in practice is you on a
# replacement Mac. A backup you cannot interpret is not a backup, and the restore
# procedure is two commands that are impossible to guess from the file names.
#
# Deterministic like every other render, so a run that changed nothing produces
# no commit.
distill_render_state_readme() {
    local out="${1:-$(distill_state_dir)/README.md}" remote title
    # Read back from git rather than a config key, so the clone line in the
    # README can never name a remote this repo does not actually push to.
    remote="$(git -C "$(distill_state_dir)" remote get-url origin 2>/dev/null || true)"
    # Normalised, because this file is TRACKED. Two Macs on one corpus that spell
    # the same remote differently — one `git@github.com:…`, one `https://…` —
    # would otherwise rewrite this line against each other on every run: a commit
    # each night that changes nothing, and a merge conflict in the one file that
    # has no business having one.
    [ -n "$remote" ] && remote="https://$(distill_remote_id "$remote")"
    # There is one of these repo per profile (…-personal, …-work), and a heading
    # that names the wrong one on the wrong remote is worse than no heading.
    title="$(basename "${remote:-claude-memory}" .git)"
    mkdir -p "$(dirname "$out")"
    {
        printf '# %s\n\n' "$title"
        printf 'The corpus behind my Claude Code memory. Written by `chezdistill`, a\n'
        printf 'nightly job in [dotfiles](https://github.com/martinzachariassen/dotfiles);\n'
        printf 'nothing here is edited by hand.\n\n'

        printf 'Each night the job reads the Claude Code sessions written since it last\n'
        printf 'looked, asks a model what is worth keeping, and stores the answer. The\n'
        printf 'rules Claude actually loads (`MAIN.md`, `Topics/`) are **not** in this\n'
        printf 'repo — they are regenerated from what is, so keeping both would be two\n'
        printf 'copies of one decision, free to disagree.\n\n'

        printf '## What is in here\n\n'
        printf -- '| Path | What it is |\n|---|---|\n'
        printf -- '| `extracts/<date>.<host>.json` | Every item the model kept, with a short quote as evidence. One file per day **per Mac**, so two machines never write the same path. **The source of truth** — everything else is derived from this. |\n'
        printf -- '| `Pinned.md` | The hand-written rules. Copied here because they are the one thing that cannot be regenerated. |\n\n'

        printf 'That is the whole repo, and the rule is simple: if a machine can regenerate\n'
        printf 'it or nobody else can use it, it is not here. Deliberately absent are\n'
        printf '`cursor.json` (how far *this* Mac has read), `spend.jsonl` (what *this* Mac\n'
        printf 'was billed), `runs.jsonl` (what *this* Mac did at 01:00) and `logs/`. All\n'
        printf 'three files are append-only, so tracking them would make two Macs conflict\n'
        printf 'on every line and quietly stop the backup that matters.\n\n'

        printf '## Restoring onto a new Mac\n\n'
        printf 'Set the dotfiles up first, then:\n\n'
        printf '```sh\n'
        printf 'git clone %s \\\n' "${remote:-<this repo>}"
        printf '    ~/.local/state/chezdistill\n'
        printf 'chezdistill --render\n'
        printf '```\n\n'
        printf '`--render` makes no model calls and costs nothing. It rebuilds `MAIN.md`,\n'
        printf '`Topics/` and `Candidates.md` from the extracts, so the new machine starts\n'
        printf 'with the memory the old one had rather than an empty one.\n\n'

        printf '## Why it is private\n\n'
        printf 'Each item carries a short quote from the conversation it came from, as\n'
        printf 'evidence for why it was kept. That is transcript text. Quotes are stripped\n'
        printf 'from items older than the retention window, but the recent ones are real,\n'
        printf 'so this repo stays private and every push is scanned by `gitleaks` first.\n'
    } >"$out"
}

# distill_state_repo_init — created on first use, and pointed at the corpus its
# profile owns (`[distill.remotes]`), so a replacement Mac clones the corpus
# instead of starting from an empty memory and nobody has to remember a
# `git remote add`. A remote already set by hand is left alone unless it is
# another profile's, which is refused — see distill_remote_conflict.
#
# What is tracked is exactly what cannot be regenerated: the extract corpus and
# `Pinned.md`. Everything else here is per-machine telemetry and is excluded —
# `cursor.json` ("how far has THIS Mac read"), `spend.jsonl` (what THIS Mac was
# billed), `runs.jsonl` (what THIS Mac did at 01:00) and `logs/` (launchd noise,
# and the one thing here that grows without bound).
#
# That split is not only about tidiness. All three telemetry files are append-only,
# so two Macs pushing to one remote would conflict on every line of them, and the
# rebase-then-push fallback below would fail silently and stop backing up the one
# thing that mattered. Tracking only the corpus makes the shared case work.
#
# Identity and signing are pinned locally rather than inherited. A global
# `commit.gpgsign = true` backed by 1Password's op-ssh-sign raises a GUI approval
# prompt, and a launchd job at 01:00 has nobody to approve it — the commit would
# hang or fail every night. Nothing here is published or attributed to anyone, so
# there is nothing for a signature to attest to.
distill_state_repo_init() {
    local repo pat
    repo="$(distill_state_dir)"
    mkdir -p "$repo" || return 1
    if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$repo" init -q >/dev/null 2>&1 || {
            distill_warn "could not init the state repo at $repo — --undo will not work"
            return 1
        }
    fi
    git -C "$repo" config commit.gpgsign false >/dev/null 2>&1 || true
    git -C "$repo" config user.name chezdistill >/dev/null 2>&1 || true
    git -C "$repo" config user.email chezdistill@localhost >/dev/null 2>&1 || true
    # Adopt before checking: a repo with no origin is not in conflict with
    # anything, it just doesn't know where it lives yet.
    distill_remote_adopt
    distill_remote_check || return 1
    distill_state_repo_pushurl
    distill_state_restore
    distill_render_state_readme
    distill_seed_pinned
    # Ensure each rule, rather than only writing the file when absent: a repo
    # initialised by an older version keeps its old .gitignore forever, and a
    # rule added later would never reach it. Untrack too — .gitignore has no
    # effect on a path that is already in the index.
    for pat in 'logs/' 'cursor.json' 'runs.jsonl' 'spend.jsonl' '*.tmp'; do
        grep -qxF "$pat" "$repo/.gitignore" 2>/dev/null && continue
        printf '%s\n' "$pat" >>"$repo/.gitignore"
    done
    git -C "$repo" ls-files -z --cached -i --exclude-standard 2>/dev/null |
        xargs -0 -r git -C "$repo" rm -q --cached -- 2>/dev/null || true
    return 0
}

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
    local main cap spent ceiling n last line f foreign url verdict va vb
    s_section "chezdistill"

    # Paths only. A remote conflict is reported below as its own line rather than
    # cutting the report short — it is the thing you opened --status to see.
    if ! _distill_preflight_paths; then
        s_fail "paths    unusable"
        return 0
    fi

    s_pass "memory   $(distill_memory_dir)"
    s_pass "state    $(distill_state_dir)"

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
    if foreign="$(distill_remote_conflict)"; then
        s_fail "backup   origin is the $foreign corpus, but this is a $(distill_profile) Mac — nothing will run"
        s_note "         git -C $(distill_state_dir) remote set-url origin $(distill_remote_url)"
    else
        n="$(git -C "$(distill_state_dir)" rev-list --count HEAD 2>/dev/null || echo 0)"
        url="$(git -C "$(distill_state_dir)" remote get-url origin 2>/dev/null || true)"
        read -r verdict va vb <<<"$(distill_backup_state)"
        case "$verdict" in
            no-repo) s_note "backup   no state repo yet — the first run creates it" ;;
            no-remote) s_warn "backup   $n commit(s), no remote — this Mac is the only copy" ;;
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
        s_warn "not one of these runs saw a single session — check: chezdistill --status"
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

# ─── Schemas ──────────────────────────────────────────────────────────────────

# One call per session, not two. Measured on real transcripts, a separate Haiku
# triage pass cost $0.05/session while the map cost $0.23 — but each call also
# re-pays ~19k tokens of cached harness context, so splitting them was buying a
# cheap gate with an expensive round trip. `items: []` is the triage verdict.
distill_schema_map() {
    cat <<'JSON'
{"type":"object","additionalProperties":false,
 "required":["items"],
 "properties":{"items":{"type":"array","items":{
   "type":"object","additionalProperties":false,
   "required":["text","detail","kind","topic","evidence","confidence"],
   "properties":{
     "text":{"type":"string","maxLength":200},
     "detail":{"type":"string"},
     "kind":{"type":"string","enum":["decisions","preferences","learnings",
             "questions_answered","open_threads","gotchas"]},
     "topic":{"type":"string"},
     "evidence":{"type":"string"},
     "confidence":{"type":"string","enum":["low","medium","high"]}}}}}}
JSON
}

# ─── Cursor ───────────────────────────────────────────────────────────────────

distill_cursor_file() {
    printf '%s/cursor.json\n' "$(distill_state_dir)"
}

# distill_cursor_read — where the job last read to. The cursor, rather than
# "yesterday", is what makes a laptop that slept through 01:00 lose nothing.
distill_cursor_read() {
    local f
    f="$(distill_cursor_file)"
    if [ -n "${DISTILL_SINCE:-}" ]; then
        printf '%s\n' "$DISTILL_SINCE"
    elif [ -f "$f" ]; then
        jq -r '.cursor // empty' "$f" 2>/dev/null || distill_iso_ago 1
    else
        distill_iso_ago 1
    fi
}

distill_cursor_write() {
    local f
    f="$(distill_cursor_file)"
    mkdir -p "$(dirname "$f")"
    jq -n --arg c "$1" '{cursor:$c}' >"$f"
}

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
            if jq -s '{items: (.[0].items + .[1] | unique)}' \
                "$out" <(jq -s '.' "$f") >"$out.tmp" 2>/dev/null &&
                mv "$out.tmp" "$out" 2>/dev/null; then
                :
            else
                rm -f "$out.tmp"
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

# ─── Rubric ───────────────────────────────────────────────────────────────────
#
# The rubric REPLACES the default system prompt. The Skill tool is unavailable
# under `--tools ""`, so the SKILL.md is read as a file here; it still doubles
# as a manually invocable `/distill` in an interactive session.

# distill_rubric — the body of the distill SKILL.md, front matter stripped.
distill_rubric() {
    local deployed repo
    deployed="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}/skills/distill/SKILL.md"
    repo="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}/src/dot_config/claude/skills/distill/SKILL.md"
    if [ -r "$deployed" ]; then
        sed '1{/^---$/,/^---$/d;}' "$deployed"
    elif [ -r "$repo" ]; then
        sed '1{/^---$/,/^---$/d;}' "$repo"
    else
        printf 'Extract durable lessons from Claude Code sessions. Answer only with the schema.\n'
    fi
}
