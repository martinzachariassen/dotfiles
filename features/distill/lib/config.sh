#!/usr/bin/env bash
# Configuration, portable dates, and the harvest cursor.
#
# Where everything lives, read once from chezmoi data, plus the date helpers
# every other module formats with (BSD on macOS, GNU in CI) and the cursor that
# records how far the last harvest got.
#
# Part of the chezdistill engine; sourced by features/distill/lib.sh, never
# on its own. See features/distill/README.md.

# ─── Config ───────────────────────────────────────────────────────────────────

_DISTILL_CFG=""
_DISTILL_DATA=""
_DISTILL_SCOPE=""

# _distill_data — all of `chezmoi data`, fetched once. Two callers want different
# parts of it (`.distill` and `.memoryScope`) and it costs a subprocess each time.
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

# distill_scope — which memory scope this Mac belongs to. A free-text label:
# two Macs that share a scope share a corpus, two Macs that don't must never
# merge theirs. It replaced `.profile`, which forced the same decision through a
# three-valued enum that the rest of the repo no longer has.
#
# The only thing in this file that reads outside the `.distill` table, and it
# earns it: the corpus a machine pushes to is a property of the machine, not of
# the config. Empty when chezmoi is not on PATH, which every caller treats as
# "no opinion" rather than as an error.
#
# `.profile` is read as a fallback so a Mac set up before the rename keeps the
# scope it already had — otherwise its corpus, stamped `personal`, would stop
# matching a machine that suddenly claims no scope at all.
#
# An EMPTY memoryScope falls through to `.profile` rather than winning, which
# `//` alone would not do: jq's alternative operator only skips null and false,
# so a saved `memoryScope = ""` — which promptStringOnce treats as a real answer
# — would shadow the profile and leave every leak-boundary check comparing "" to
# "". That passes, silently, which is the one outcome this whole file exists to
# prevent.
distill_scope() {
    if [ -z "$_DISTILL_SCOPE" ]; then
        if [ -n "${DISTILL_SCOPE:-}" ]; then
            _DISTILL_SCOPE="$DISTILL_SCOPE"
        elif [ -n "${DISTILL_PROFILE:-}" ]; then
            # Retired env name, honoured for one release.
            _DISTILL_SCOPE="$DISTILL_PROFILE"
        else
            _DISTILL_SCOPE="$(_distill_data | jq -r '
                [.memoryScope, .profile]
                | map(select(type == "string" and . != ""))
                | first // empty' 2>/dev/null)"
        fi
    fi
    printf '%s\n' "$_DISTILL_SCOPE"
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
