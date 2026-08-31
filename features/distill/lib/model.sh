#!/usr/bin/env bash
# The one place that calls the model.
#
# Every `claude -p` invocation, and the JSON schema and rubric it is held to.
# The model extracts; bash decides and writes. Nothing here has write access —
# each call passes `--tools ""`.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

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
