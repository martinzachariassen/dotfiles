#!/usr/bin/env bash
# distill.sh — the chezdistill engine: harvest Claude Code transcripts, distil
# them into the Obsidian vault, and render MAIN.md from a derived ledger.
#
# Design principle: the model extracts and narrates, bash decides and writes.
# Every judgement that must be reproducible on two machines — scope, hit counts,
# what earns a place in MAIN, what gets demoted — is computed here from the
# extract corpus. No model invocation in this file has write access.
# shellcheck disable=SC2034,SC2329

[ -n "${__DOTFILES_DISTILL_SH:-}" ] && return 0
__DOTFILES_DISTILL_SH=1

# ─── Config ───────────────────────────────────────────────────────────────────

_DISTILL_CFG=""

# distill_config — the `.distill` table from .chezmoidata, fetched once.
distill_config() {
    if [ -z "$_DISTILL_CFG" ]; then
        if [ -n "${DISTILL_CONFIG_JSON:-}" ]; then
            _DISTILL_CFG="$DISTILL_CONFIG_JSON"
        else
            _DISTILL_CFG="$(chezmoi data --format=json 2>/dev/null |
                jq -c '.distill // {}' 2>/dev/null)"
        fi
        [ -n "$_DISTILL_CFG" ] || _DISTILL_CFG='{}'
    fi
    printf '%s\n' "$_DISTILL_CFG"
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

# distill_preflight — every precondition, checked before any processing.
# Exports DISTILL_VAULT and DISTILL_ROOT on success.
# 0 = go · 1 = broken/unwritable (real failure) · 2 = absent (expected, not an error)
distill_preflight() {
    local vault folder

    if ! command -v jq >/dev/null 2>&1; then
        fail "jq is required but not on PATH"
        return 1
    fi

    vault="$(distill_expand "$(distill_cfg vaultPath)")"
    folder="$(distill_cfg folder 30-Claude)"

    if [ -z "$vault" ] || [ ! -d "$vault" ]; then
        info "vault not found at ${vault:-<unset>} — nothing to do"
        return 2
    fi
    if [ ! -d "$vault/.obsidian" ]; then
        info "$vault has no .obsidian — not a vault (unmounted or not cloned yet)"
        return 2
    fi
    if [ ! -d "$vault/$folder" ]; then
        info "$vault/$folder does not exist — create it in Obsidian first"
        return 2
    fi
    if [ ! -w "$vault/$folder" ]; then
        fail "$vault/$folder is not writable"
        return 1
    fi
    if ! git -C "$vault" rev-parse --git-dir >/dev/null 2>&1; then
        fail "$vault is not a git repo"
        return 1
    fi
    if [ -z "$(git -C "$vault" remote 2>/dev/null)" ]; then
        fail "$vault has no configured git remote"
        return 1
    fi

    DISTILL_VAULT="$vault"
    DISTILL_ROOT="$vault/$folder"
    export DISTILL_VAULT DISTILL_ROOT
    return 0
}

# distill_state_dir — .state, created on demand inside an already-present root.
distill_state_dir() {
    printf '%s\n' "$DISTILL_ROOT/.state"
}

distill_host() {
    printf '%s\n' "${DISTILL_HOST_OVERRIDE:-$(hostname -s)}"
}

# ─── Harvest ──────────────────────────────────────────────────────────────────

# distill_session_files — transcripts touched recently, subagents excluded.
# `find` is shadowed by bfs in this user's interactive shell, hence the full path.
distill_session_files() {
    local root expanded
    while IFS= read -r root; do
        [ -n "$root" ] || continue
        expanded="$(distill_expand "$root")"
        [ -d "$expanded" ] || continue
        /usr/bin/find "$expanded" -type f -name '*.jsonl' \
            -not -path '*/subagents/*' -mtime -"${DISTILL_MTIME_DAYS:-2}" 2>/dev/null
    done < <(distill_cfg_list transcriptRoots)
}

# distill_classify_origin CWD — work | personal | unknown.
# Resolved here, at harvest, on the machine that still has the repo on disk.
# Git remotes are authoritative and self-maintaining; paths are the fallback for
# directories that aren't repos. Anything else is `unknown` on purpose: it lands
# in Inbox and never in MAIN, so a missing pattern is visible rather than silent.
distill_classify_origin() {
    local cwd="$1" remote pat expanded
    [ -n "$cwd" ] || {
        echo unknown
        return 0
    }

    remote="$(git -C "$cwd" remote get-url origin 2>/dev/null || true)"
    if [ -n "$remote" ]; then
        while IFS= read -r pat; do
            [ -n "$pat" ] || continue
            case "$remote" in
                *"$pat"*)
                    echo work
                    return 0
                    ;;
            esac
        done < <(distill_cfg_list workRemotes)
    fi

    while IFS= read -r pat; do
        [ -n "$pat" ] || continue
        expanded="$(distill_expand "$pat")"
        case "$cwd" in
            "$expanded"*)
                echo work
                return 0
                ;;
        esac
    done < <(distill_cfg_list workPaths)

    while IFS= read -r pat; do
        [ -n "$pat" ] || continue
        expanded="$(distill_expand "$pat")"
        case "$cwd" in
            "$expanded"*)
                echo personal
                return 0
                ;;
        esac
    done < <(distill_cfg_list personalPaths)

    printf '%s\t%s\n' "$cwd" "${remote:--}" >>"${DISTILL_UNMATCHED:-/dev/null}"
    echo unknown
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

# distill_dates — the calendar days a filtered stream spans.
distill_dates() {
    jq -r '.t[0:10]' | sort -u
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
        dim "dry-run \$ claude -p --model $model --tools \"\" (payload on stdin)"
        echo '{}'
        return 0
    fi

    envelope="$(claude -p \
        --model "$model" \
        --no-session-persistence \
        --tools "" \
        --system-prompt-file "$sysfile" \
        --json-schema "$(cat "$schemafile")" \
        --max-budget-usd "$budget" \
        --output-format json \
        "$prompt" 2>&1)" || {
        fail "claude invocation failed for model $model"
        return 1
    }

    if ! printf '%s' "$envelope" | jq -e . >/dev/null 2>&1; then
        fail "claude returned non-JSON output"
        printf '%s\n' "$envelope" | head -3 >&2
        return 1
    fi

    distill_spend_record "$(printf '%s' "$envelope" | jq -r '.total_cost_usd // 0')"

    if [ "$(printf '%s' "$envelope" | jq -r '.is_error // false')" = "true" ]; then
        err="$(printf '%s' "$envelope" | jq -r '.result // .subtype // "unknown"')"
        fail "claude reported an error: $err"
        return 1
    fi

    printf '%s' "$envelope" | jq -e '.structured_output' 2>/dev/null || {
        fail "claude returned no structured output"
        return 1
    }
}

# ─── Spend ────────────────────────────────────────────────────────────────────
#
# Append-only, one file per machine so the two never conflict in git, but summed
# across all of them: the quota being protected belongs to the account, not the
# laptop.

distill_spend_file() {
    printf '%s/spend/%s.jsonl\n' "$(distill_state_dir)" "$(distill_host)"
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

# distill_spend_7d — total spend across every machine over the last 7 days.
distill_spend_7d() {
    local since dir
    since="$(distill_iso_ago 7)"
    dir="$(distill_state_dir)/spend"
    [ -d "$dir" ] || {
        echo 0
        return 0
    }
    cat "$dir"/*.jsonl 2>/dev/null |
        jq -s --arg since "$since" \
            '[.[] | select(.t > $since) | .usd] | add // 0' 2>/dev/null || echo 0
}

# distill_spend_ok — the rolling ceiling, checked in preflight so a runaway
# cannot quietly bill for a week before anyone notices.
distill_spend_ok() {
    local spent ceiling
    spent="$(distill_spend_7d)"
    ceiling="$(distill_cfg maxSpendUsd7d 15.0)"
    if jq -n --argjson s "$spent" --argjson c "$ceiling" -e '$s >= $c' >/dev/null 2>&1; then
        fail "7-day spend \$$spent has reached the \$$ceiling ceiling — refusing to start"
        return 1
    fi
    return 0
}

# ─── Ledger ───────────────────────────────────────────────────────────────────
#
# One file per entry, because a single ledger.json would conflict in git on every
# run with two machines writing. The id is a hash of the normalised text, so the
# same fact found on both machines lands on the same path with the same content.
#
# The files hold only what cannot be recomputed: text, kind, topic, first_seen and
# any supersession. Everything the renderer needs to make a decision — hit counts,
# scope, recency — is DERIVED from the extract corpus on every run. That is what
# makes rendering idempotent, and idempotence is what makes it safe for the second
# machine to re-run a day the first machine already summarised.

distill_sha() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | cut -c1-12
    else
        sha256sum | cut -c1-12
    fi
}

# distill_entry_id TEXT — stable across machines and across re-runs.
distill_entry_id() {
    printf '%s' "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr -s '[:space:]' ' ' |
        sed -e 's/^ *//' -e 's/[ .,;:!?]*$//' |
        distill_sha
}

distill_ledger_dir() {
    printf '%s/ledger\n' "$(distill_state_dir)"
}

distill_extracts_dir() {
    printf '%s/extracts\n' "$(distill_state_dir)"
}

# distill_ledger_upsert ID TEXT KIND TOPIC — never overwrites first_seen.
distill_ledger_upsert() {
    local id="$1" text="$2" kind="$3" topic="$4" dir f
    dir="$(distill_ledger_dir)"
    mkdir -p "$dir"
    f="$dir/$id.json"
    [ -f "$f" ] && return 0
    jq -n --arg id "$id" --arg text "$text" --arg kind "$kind" \
        --arg topic "$topic" --arg first "$(date -u +%Y-%m-%d)" \
        '{id:$id, text:$text, kind:$kind, topic:$topic,
          first_seen:$first, superseded_by:null}' >"$f"
}

# distill_derive — the single source of truth for every rendering decision.
# Aggregates every machine's extracts into one NDJSON stream:
#   {id, text, kind, topic, hits, origins[], scope, last_seen, superseded_by}
#
# scope: any `unknown` sighting keeps the entry out of MAIN entirely; seen under
# both work and personal earns `always`; otherwise the single origin it was seen
# under. Derived, never asserted — a rule earns `always` by actually recurring in
# both contexts.
distill_derive() {
    local ex led
    ex="$(distill_extracts_dir)"
    led="$(distill_ledger_dir)"
    [ -d "$ex" ] || return 0

    /usr/bin/find "$ex" -type f -name '*.json' 2>/dev/null |
        while IFS= read -r f; do
            jq -c --arg date "$(basename "$(dirname "$f")")" \
                '.items[]? | {text, detail, kind, topic, origin, session, date:$date}' \
                "$f" 2>/dev/null
        done |
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            printf '%s\n' "$item" |
                jq -c --arg id "$(distill_entry_id \
                    "$(printf '%s' "$item" | jq -r '.text')")" '. + {id:$id}'
        done |
        jq -s -c --arg leddir "$led" '
            group_by(.id)[]
            | { id: .[0].id,
                text: .[0].text,
                detail: (.[0].detail // ""),
                kind: .[0].kind,
                topic: (.[0].topic // "General"),
                hits: ([.[].session] | unique | length),
                origins: ([.[].origin] | unique),
                last_seen: ([.[].date] | max),
                first_seen: ([.[].date] | min) }
            | . + { scope: (
                if (.origins | index("unknown")) then "unknown"
                elif ((.origins | index("work")) and (.origins | index("personal")))
                    then "always"
                elif (.origins | index("work")) then "work"
                else "personal" end) }'
}

# distill_superseded ID — the id that replaced this one, empty when current.
distill_superseded() {
    local f
    f="$(distill_ledger_dir)/$1.json"
    [ -f "$f" ] || return 0
    jq -r '.superseded_by // empty' "$f" 2>/dev/null
}

# ─── Rendering ────────────────────────────────────────────────────────────────
#
# MAIN.md is rendered, never written by the model. Identical input therefore
# yields byte-identical output on both machines, which is the whole reason two
# machines can write to the same vault without a lock.
#
# Eligibility for MAIN, all derived:
#   hits >= minHits          the promotion gate — one misreading can't become a rule
#   scope != unknown         unclassified material never reaches a scoped section
#   not superseded           a newer decision has replaced it
#   last_seen >= cutoff      still current; stale entries fall back to Topics
#
# Note this differs from the original plan, which demoted on
# "not reinforced for N days AND hits < minHits". That predicate can never fire:
# anything in MAIN already has hits >= minHits by the promotion gate, so the age
# rule would have been dead code and MAIN would only ever have grown. Age alone
# demotes here; `Pinned.md` is the channel for things that must never age out.

distill_eligible() {
    local cutoff minhits
    minhits="$(distill_cfg minHits 2)"
    cutoff="$(date -u -v-"$(distill_cfg demoteAfterDays 21)"d +%Y-%m-%d 2>/dev/null ||
        date -u -d "$(distill_cfg demoteAfterDays 21) days ago" +%Y-%m-%d)"
    distill_derive | jq -c --argjson minhits "$minhits" --arg cutoff "$cutoff" '
        . + { eligible: (.hits >= $minhits
                         and .scope != "unknown"
                         and .last_seen >= $cutoff),
              score: (.hits * 100000 + (.last_seen | gsub("-";"") | tonumber % 100000)) }'
}

_distill_section_title() {
    case "$1" in
        always) printf 'Always' ;;
        work) printf 'Work only — applies when the git remote or path matches a work pattern' ;;
        personal) printf 'Personal only — applies otherwise' ;;
    esac
}

# distill_render_main [OUTFILE] — deterministic; running it twice is a no-op.
distill_render_main() {
    local out="${1:-$DISTILL_ROOT/MAIN.md}"
    local pinned="$DISTILL_ROOT/Pinned.md"
    local cap base tmp chosen scope line used
    cap="$(distill_cfg mainCapBytes 6144)"
    tmp="$(mktemp)"
    chosen="$(mktemp)"

    {
        printf '<!-- Generated by chezdistill. Do not edit: edit Pinned.md instead. -->\n\n'
        if [ -f "$pinned" ]; then
            cat "$pinned"
            printf '\n'
        fi
    } >"$tmp"

    base="$(wc -c <"$tmp" | tr -d ' ')"
    if [ "$base" -gt "$cap" ]; then
        warn "Pinned.md alone exceeds the ${cap}B cap — nothing else will fit"
    fi

    # Reserve every section header up front, even for sections that may end up
    # empty. Whether a section is used depends on what gets selected, and what
    # gets selected depends on the remaining budget — so the reservation is made
    # unconditionally to keep the cap a guarantee rather than an estimate.
    used="$base"
    for scope in always work personal; do
        line="## $(_distill_section_title "$scope")"
        used=$((used + ${#line} + 3))
    done
    # Highest score first, ties broken by id so the order is machine-independent.
    distill_eligible |
        jq -r 'select(.eligible) | [(.score|tostring), .scope, .topic, .id, .text] | @tsv' |
        sort -t"$(printf '\t')" -k1,1nr -k4,4 |
        while IFS=$'\t' read -r _ scope topic id text; do
            line="- $text"
            [ $((used + ${#line} + 1)) -le "$cap" ] || break
            used=$((used + ${#line} + 1))
            printf '%s\t%s\t%s\t%s\n' "$scope" "$topic" "$id" "$text"
        done >"$chosen"

    # Only these three scopes are ever emitted, which is a second, independent
    # guard on `unknown`: even if the eligibility filter above were broken, an
    # unclassified entry still has no section to land in. Verified by mutation —
    # both guards must be disabled before tests/distill.bats goes red.
    for scope in always work personal; do
        if grep -q "^$scope$(printf '\t')" "$chosen" 2>/dev/null; then
            printf '\n## %s\n\n' "$(_distill_section_title "$scope")" >>"$tmp"
            grep "^$scope$(printf '\t')" "$chosen" |
                sort -t"$(printf '\t')" -k2,2 -k3,3 |
                while IFS=$'\t' read -r _ _ _ text; do
                    printf -- '- %s\n' "$text" >>"$tmp"
                done
        fi
    done

    mv "$tmp" "$out"
    rm -f "$chosen"

    used="$(wc -c <"$out" | tr -d ' ')"
    [ "$used" -le "$cap" ] || warn "MAIN.md is ${used}B, over the ${cap}B cap"
}

# distill_render_inbox — everything that did not earn a place in MAIN and why.
distill_render_inbox() {
    local out="${1:-$DISTILL_ROOT/Inbox/Candidates.md}"
    local minhits
    minhits="$(distill_cfg minHits 2)"
    mkdir -p "$(dirname "$out")"
    {
        printf '<!-- Generated by chezdistill. Entries here affect nothing. -->\n\n'
        printf '# Candidates\n\n'
        printf 'Seen once, or from a project that matched no origin pattern.\n'
        printf 'They reach MAIN.md once seen in at least %s distinct session(s)\n' "$minhits"
        printf 'with a known origin.\n'
        printf '\n## Awaiting a second sighting\n\n'
        distill_eligible |
            jq -r --argjson m "$minhits" \
                'select(.scope != "unknown" and .hits < $m)
                 | "- \(.text)  ·  \(.scope), \(.hits) hit(s), last seen \(.last_seen)"' |
            sort
        printf '\n## Unclassified origin\n\n'
        printf 'Add a pattern to `workRemotes`/`workPaths`/`personalPaths` in `distill.toml`.\n\n'
        distill_eligible |
            jq -r 'select(.scope == "unknown")
                   | "- \(.text)  ·  \(.hits) hit(s), last seen \(.last_seen)"' |
            sort
    } >"$out"
}

# distill_render_topics — the free tier. MAIN carries the terse rule (capped at
# 200 chars by the schema, because every byte is re-read in every session); the
# full `detail` lands here, where it is read only when Claude follows a wikilink
# and length therefore costs nothing.
distill_render_topics() {
    local dir="${1:-$DISTILL_ROOT/Topics}"
    local topic
    mkdir -p "$dir"

    distill_eligible |
        jq -r 'select(.scope != "unknown") | .topic' | sort -u |
        while IFS= read -r topic; do
            [ -n "$topic" ] || continue
            {
                printf '<!-- Generated by chezdistill. -->\n\n# %s\n\n' "$topic"
                # Sorted inside jq: these records are multi-line, and piping
                # them through sort(1) would interleave lines across entries.
                distill_eligible |
                    jq -s -r --arg t "$topic" \
                        '[.[] | select(.topic == $t and .scope != "unknown")]
                         | sort_by(.text)[]
                         | "## \(.text)\n\n\(.detail)\n\n*\(.scope) · \(.hits) hit(s) · last seen \(.last_seen)*\n"'
            } >"$dir/$topic.md"
        done
}

# distill_main_diff BEFORE AFTER — the audit trail for the daily report.
distill_main_diff() {
    local before="$1" after="$2"
    diff <(grep '^- ' "$before" 2>/dev/null | sort) \
        <(grep '^- ' "$after" 2>/dev/null | sort) |
        sed -n -e 's/^> - /+ /p' -e 's/^< - /- /p' |
        cut -c1-100
}

# ─── Daily and weekly reports ─────────────────────────────────────────────────
#
# The item sections are RENDERED from the extract corpus, not spliced into an
# existing file. That is a deliberate simplification of the original plan: since
# the items are a pure function of every machine's extracts, recomputing them is
# both idempotent and machine-independent, and "keep the existing lines verbatim"
# stops being an instruction the model could disobey. Only the narrative is
# model-written, and it is stored beside the extracts so a re-render preserves it.

distill_narrative_file() {
    printf '%s/narratives/%s.md\n' "$(distill_state_dir)" "$1"
}

distill_extract_files() {
    local d
    d="$(distill_extracts_dir)/$1"
    [ -d "$d" ] || return 0
    /usr/bin/find "$d" -type f -name '*.json' 2>/dev/null | sort
}

# distill_sources_fingerprint DATE — hostname + content hash per contributing
# machine. This is the cheap check that makes the second machine a no-op.
distill_sources_fingerprint() {
    local f host
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        host="$(basename "$f" .json)"
        printf '%s  %s\n' "$host" "$(distill_sha <"$f")"
    done < <(distill_extract_files "$1")
}

# distill_sources_match DATE — 0 when the report already reflects every extract.
distill_sources_match() {
    local date="$1" recorded current
    recorded="$(distill_narrative_file "$date")"
    recorded="${recorded%.md}.sources"
    [ -f "$recorded" ] || return 1
    current="$(distill_sources_fingerprint "$date")"
    [ "$(cat "$recorded")" = "$current" ]
}

# distill_render_daily DATE — deterministic given the extracts and the narrative.
distill_render_daily() {
    local date="$1" out narrative origins sources scope kind items
    out="$DISTILL_ROOT/Daily/$date.md"
    narrative="$(distill_narrative_file "$date")"
    items="$(mktemp)"
    mkdir -p "$(dirname "$out")"

    origins="$(distill_date_items "$date" | jq -r '.origin' | sort -u |
        paste -sd, - | sed 's/,/, /g')"
    sources="$(distill_sources_fingerprint "$date" | awk '{print $1}' |
        paste -sd, - | sed 's/,/, /g')"

    {
        printf -- '---\norigins: [%s]\nsources: [%s]\n---\n\n' \
            "${origins:-}" "${sources:-}"

        if [ -s "$DISTILL_ROOT/.state/main-diff-$date.txt" ]; then
            printf '## MAIN.md changes\n\n'
            cat "$DISTILL_ROOT/.state/main-diff-$date.txt"
            printf '\n'
        fi

        if [ -f "$narrative" ]; then
            printf '## Summary\n\n'
            cat "$narrative"
            printf '\n'
        fi

        for scope in personal work unknown; do
            distill_date_items "$date" |
                jq -e --arg s "$scope" 'select(.origin == $s)' >/dev/null 2>&1 || continue
            case "$scope" in
                personal) printf '## Personal\n' ;;
                work) printf '## Work\n' ;;
                unknown) printf '## Unclassified\n' ;;
            esac
            for kind in decisions preferences learnings questions_answered \
                open_threads gotchas; do
                distill_date_items "$date" |
                    jq -r --arg s "$scope" --arg k "$kind" \
                        'select(.origin == $s and .kind == $k)
                         | "- \(.text)  ·  \(.tool // "claude-code")"' |
                    sort -u >"$items"
                [ -s "$items" ] || continue
                printf '\n### %s\n\n' "$(distill_kind_title "$kind")"
                cat "$items"
            done
            printf '\n'
        done

        printf '## Sources\n\n'
        distill_sources_fingerprint "$date"
    } >"$out"
    rm -f "$items"
}

distill_kind_title() {
    case "$1" in
        decisions) printf 'Decisions' ;;
        preferences) printf 'Preferences' ;;
        learnings) printf 'Learnings' ;;
        questions_answered) printf 'Questions answered' ;;
        open_threads) printf 'Open threads' ;;
        gotchas) printf 'Gotchas' ;;
    esac
}

# distill_date_items DATE — every machine's items for one day, flattened.
distill_date_items() {
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        jq -c '.items[]?' "$f" 2>/dev/null
    done < <(distill_extract_files "$1")
}

# ─── Git ──────────────────────────────────────────────────────────────────────
#
# Being offline is not an error: the work is done, committed locally, and pushed
# by whichever run next has a network. Only the vault is touched, never the repo
# this script ships in.

# Never let the network block a headless job. Without these an unreachable remote
# makes git sit on an SSH or credential prompt forever, and a launchd job has no
# terminal to answer it — the run hangs until the machine is rebooted.
distill_git_env() {
    export GIT_TERMINAL_PROMPT=0
    export GIT_ASKPASS=/usr/bin/true
    export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
}

distill_git_pull() {
    [ "${DRY_RUN:-0}" = "1" ] && return 0
    distill_git_env
    git -C "$DISTILL_VAULT" pull --rebase --autostash >/dev/null 2>&1 ||
        warn "could not pull the vault (offline?) — continuing locally"
}

# distill_git_push MESSAGE — commit and push, rebasing once on rejection.
distill_git_push() {
    local msg="$1" folder
    folder="$(distill_cfg folder 30-Claude)"
    [ "${DRY_RUN:-0}" = "1" ] && {
        dim "dry-run \$ git commit -m '$msg' && git push"
        return 0
    }

    distill_git_env
    git -C "$DISTILL_VAULT" add -- "$folder" >/dev/null 2>&1 || true
    git -C "$DISTILL_VAULT" diff --cached --quiet 2>/dev/null && return 0
    git -C "$DISTILL_VAULT" commit -q -m "$msg" >/dev/null 2>&1 || {
        warn "vault commit failed"
        return 1
    }

    if ! git -C "$DISTILL_VAULT" push -q >/dev/null 2>&1; then
        git -C "$DISTILL_VAULT" pull --rebase --autostash >/dev/null 2>&1 || true
        git -C "$DISTILL_VAULT" push -q >/dev/null 2>&1 ||
            info "push deferred — the next run will carry it"
    fi
}

# ─── Skills ───────────────────────────────────────────────────────────────────
#
# Skill discovery is exactly one level deep — verified on this install:
# ~/.config/claude/skills/<name>/SKILL.md is found, skills/generated/<name>/ is
# not. So generated skills are mirrored FLAT under a `distilled-` prefix, which
# is also the only glob this mirror is allowed to touch: `skills/distill/` and
# `skills/distill-weekly/` are chezmoi-managed and sit in the same directory.

distill_skills_target() {
    printf '%s/skills\n' "${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}"
}

distill_sync_skills() {
    local src dest name
    src="$(distill_state_dir)/skills"
    dest="$(distill_skills_target)"
    [ -d "$src" ] || return 0
    mkdir -p "$dest"

    for d in "$dest"/distilled-*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        [ -d "$src/${name#distilled-}" ] || rm -rf "$d"
    done

    for d in "$src"/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        mkdir -p "$dest/distilled-$name"
        cp -f "$d/SKILL.md" "$dest/distilled-$name/SKILL.md" 2>/dev/null || true
    done
}

# ─── Status ───────────────────────────────────────────────────────────────────

distill_status() {
    local main cap spent ceiling n
    s_section "chezdistill"

    if distill_preflight; then
        s_pass "vault    $DISTILL_ROOT"
    else
        case "$?" in
            2) s_warn "vault    not available — the job would exit without doing anything" ;;
            *) s_fail "vault    unusable" ;;
        esac
        return 0
    fi

    main="$DISTILL_ROOT/MAIN.md"
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

    n="$(/usr/bin/find "$(distill_ledger_dir)" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
    s_note "ledger   ${n} entries"

    n="$(distill_derive | jq -s '[.[] | select(.scope == "unknown")] | length' 2>/dev/null || echo 0)"
    if [ "${n:-0}" -gt 0 ]; then
        s_warn "origin   ${n} entries unclassified — add patterns to distill.toml"
        distill_derive | jq -r 'select(.scope == "unknown") | "           \(.text[0:60])"' 2>/dev/null | head -5
    else
        s_pass "origin   every entry classified"
    fi

    spent="$(distill_spend_7d)"
    ceiling="$(distill_cfg maxSpendUsd7d 15.0)"
    s_note "spend    \$$spent of \$$ceiling over 7 days"

    for f in "$(distill_state_dir)"/cursor-*.json; do
        [ -f "$f" ] || continue
        s_note "cursor   $(basename "$f" .json | sed 's/^cursor-//') → $(jq -r '.cursor // "?"' "$f")"
    done
}

# ─── Schemas ──────────────────────────────────────────────────────────────────

distill_schema_triage() {
    cat <<'JSON'
{"type":"object","additionalProperties":false,
 "required":["worth","reason"],
 "properties":{"worth":{"type":"boolean"},"reason":{"type":"string"}}}
JSON
}

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

distill_schema_narrative() {
    cat <<'JSON'
{"type":"object","additionalProperties":false,
 "required":["summary"],
 "properties":{"summary":{"type":"string"}}}
JSON
}

# ─── Cursor ───────────────────────────────────────────────────────────────────

distill_cursor_file() {
    printf '%s/cursor-%s.json\n' "$(distill_state_dir)" "$(distill_host)"
}

# distill_cursor_read — where this machine last read to. The cursor, rather than
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
    jq -n --arg c "$1" --arg h "$(distill_host)" \
        '{host:$h, cursor:$c}' >"$f"
}

# ─── Nightly ──────────────────────────────────────────────────────────────────

distill_run_daily() {
    local since now host tmp sysfile schema filtered turns origin cwd
    local sess title mapped date dates n_seen n_kept

    distill_spend_ok || return 1
    distill_git_pull

    since="$(distill_cursor_read)"
    now="$(distill_iso_now)"
    host="$(distill_host)"
    tmp="$(mktemp -d)"
    export DISTILL_UNMATCHED="$tmp/unmatched"
    : >"$DISTILL_UNMATCHED"

    sysfile="$tmp/rubric.md"
    distill_rubric >"$sysfile"
    schema="$tmp/map.json"
    distill_schema_map >"$schema"

    info "reading transcripts since $since"
    n_seen=0
    n_kept=0

    while IFS= read -r sess; do
        [ -n "$sess" ] || continue
        n_seen=$((n_seen + 1))
        filtered="$tmp/$(basename "$sess" .jsonl).ndjson"
        distill_filter "$sess" "$since" | distill_dedupe >"$filtered"
        [ -s "$filtered" ] || continue

        turns="$(distill_turns <"$filtered")"
        if [ "${turns:-0}" -lt "$(distill_cfg minTurns 3)" ]; then
            dim "skip $(basename "$sess" .jsonl) — only ${turns} typed turn(s)"
            continue
        fi

        cwd="$(jq -r 'select(.c != null) | .c' <"$filtered" | head -1)"
        origin="$(distill_classify_origin "$cwd")"
        title="$(distill_session_title "$sess")"
        date="$(jq -r '.t[0:10]' <"$filtered" | head -1)"

        mapped="$(distill_claude "$(distill_cfg mapModel sonnet)" "$sysfile" "$schema" \
            "Session title: ${title:-untitled}. Extract durable items, or none." \
            <"$filtered")" || continue

        if [ "$(printf '%s' "$mapped" | jq -r '.items | length')" = "0" ]; then
            dim "skip $(basename "$sess" .jsonl) — nothing durable in it"
            continue
        fi

        printf '%s\n' "$mapped" |
            jq -c --arg o "$origin" --arg h "$host" --arg s "$(basename "$sess" .jsonl)" \
                --arg c "$cwd" --arg tool "${DISTILL_TOOL:-claude-code}" \
                '.items[] | . + {origin:$o, host:$h, session:$s, cwd:$c, tool:$tool}' \
                >>"$tmp/items-$date.ndjson"
        n_kept=$((n_kept + 1))
    done < <(distill_session_files)

    ok "$n_kept of $n_seen session(s) yielded items"

    dates=""
    for f in "$tmp"/items-*.ndjson; do
        [ -f "$f" ] || continue
        date="$(basename "$f" .ndjson)"
        date="${date#items-}"
        mkdir -p "$(distill_extracts_dir)/$date"
        jq -s '{items: .}' "$f" >"$(distill_extracts_dir)/$date/$host.json"
        dates="$dates $date"
    done

    distill_finish_dates "$dates" "$tmp"
    distill_cursor_write "$now"
    rm -rf "$tmp"
}

# distill_finish_dates DATES TMPDIR — narrate, render and publish.
distill_finish_dates() {
    local dates="$1" tmp="$2" date before
    local main="$DISTILL_ROOT/MAIN.md"

    before="$tmp/main-before.md"
    cp -f "$main" "$before" 2>/dev/null || : >"$before"
    mkdir -p "$(distill_state_dir)/narratives"

    for date in $dates; do
        if distill_sources_match "$date"; then
            dim "$date already reflects every machine's extracts — nothing to do"
            continue
        fi
        distill_narrate "$date" "$tmp"
    done

    distill_render_main
    distill_render_inbox
    distill_render_topics

    for date in $dates; do
        distill_main_diff "$before" "$main" >"$DISTILL_ROOT/.state/main-diff-$date.txt"
        distill_render_daily "$date"
        distill_sources_fingerprint "$date" \
            >"$(distill_state_dir)/narratives/$date.sources"
    done

    distill_guard_secrets || return 1
    distill_sync_skills
    distill_git_push "chore(distill): report for${dates}"
}

# distill_narrate DATE TMPDIR — the one model call that writes prose.
distill_narrate() {
    local date="$1" tmp="$2" out
    out="$(distill_narrative_file "$date")"
    mkdir -p "$(dirname "$out")"
    distill_date_items "$date" |
        jq -s -r 'map("- [\(.kind)] \(.text)") | join("\n")' |
        distill_claude "$(distill_cfg narrateModel opus)" "$tmp/rubric.md" \
            <(distill_schema_narrative) \
            "Write a short summary of what changed on $date, from these items." |
        jq -r '.summary // empty' >"$out"
}

# distill_guard_secrets — extracts hold near-verbatim conversation text and must
# be committed for the two machines to merge, so they are swept too.
distill_guard_secrets() {
    command -v gitleaks >/dev/null 2>&1 || {
        warn "gitleaks not installed — skipping the secret sweep"
        return 0
    }
    if ! gitleaks dir "$DISTILL_ROOT" --redact --no-banner >/dev/null 2>&1; then
        fail "gitleaks found something in $DISTILL_ROOT — not committing"
        return 1
    fi
    return 0
}

# ─── Weekly ───────────────────────────────────────────────────────────────────

distill_run_weekly() {
    local week out tmp
    distill_spend_ok || return 1
    distill_git_pull

    week="$(date -u +%G-W%V)"
    out="$DISTILL_ROOT/Weekly/$week.md"
    tmp="$(mktemp -d)"
    distill_rubric >"$tmp/rubric.md"
    mkdir -p "$(dirname "$out")"

    distill_render_main
    distill_render_inbox
    distill_render_topics

    {
        printf -- '---\nweek: %s\n---\n\n# %s\n\n' "$week" "$week"
        printf '## Summary\n\n'
        distill_derive |
            jq -s -r 'map("- [\(.scope)] \(.text)") | join("\n")' |
            distill_claude "$(distill_cfg narrateModel opus)" "$tmp/rubric.md" \
                <(distill_schema_narrative) \
                "Write the weekly review for $week from these ledger entries." |
            jq -r '.summary // empty'
        printf '\n## Not in MAIN.md\n\n'
        printf 'Below the promotion gate, stale, or unclassified — see [[Candidates]].\n\n'
        distill_eligible |
            jq -r 'select(.eligible | not)
                   | "- \(.text)  ·  \(.scope), \(.hits) hit(s), last seen \(.last_seen)"' |
            sort
    } >"$out"

    distill_guard_secrets || {
        rm -rf "$tmp"
        return 1
    }
    distill_sync_skills
    distill_git_push "chore(distill): weekly review $week"
    rm -rf "$tmp"
}

# ─── Rubric ───────────────────────────────────────────────────────────────────
#
# The rubric REPLACES the default system prompt. The Skill tool is unavailable
# under `--tools ""`, so the SKILL.md is read as a file here; it still doubles as
# a manually invocable `/distill` in an interactive session.

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
