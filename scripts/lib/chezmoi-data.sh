#!/usr/bin/env bash
# chezmoi-data.sh — read chezmoi `[data]` values without a hard jq dependency.
#
# One reader, used everywhere the scripts need to know the active profile,
# feature toggles, or signing key. Before this lib the same jq-or-sed fallback
# was hand-copied into install.sh, doctor.sh, and dotfiles-config.sh, each with
# subtly different regexes. Keeping it in one place means the parsing is fixed
# once and stays consistent.
#
# Two consumption modes:
#   - sourced   — doctor.sh / dotfiles-config.sh `. scripts/lib/chezmoi-data.sh`
#   - inlined   — install.sh embeds the region between the @inline markers below
#                 (it runs via `curl | bash` before the repo exists on disk, so
#                 it cannot source). See scripts/build-install.sh.
#
# jq is preferred when present (robust JSON), with a sed fallback so a fresh Mac
# without jq still reads its own config. The functions echo the empty string for
# a missing key; callers apply their own defaults.
#
# The functions are consumed by sourcing/inlining callers, so they read as
# "unused" and "unreachable" within this file. Suppress those false positives.
# shellcheck disable=SC2034,SC2329

# Source guard (kept OUTSIDE the @inline region: a bare `return 0` at install.sh
# top level would be an error, and install.sh embeds this exactly once anyway).
[ -n "${__DOTFILES_CHEZMOI_DATA_SH:-}" ] && return 0
__DOTFILES_CHEZMOI_DATA_SH=1

# @inline-begin
# cm_data_json — the chezmoi data model as JSON, or "{}" if chezmoi can't run.
cm_data_json() {
    chezmoi data --format=json 2>/dev/null || echo '{}'
}

# cm_data_string JSON KEY — a top-level string value (e.g. profile, signingKey),
# or "" if absent.
cm_data_string() {
    local json="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$json" | jq -r --arg key "$key" '.[$key] // empty'
    else
        printf '%s\n' "$json" |
            sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" |
            sed '/^$/d' |
            tail -1
    fi
}

# cm_data_bool JSON KEY — a boolean value, checked at the top level and then
# under `.features` (so `cm_data_bool "$json" macApps` finds features.macApps).
# Echoes "true"/"false", or "" if the key is absent; callers apply a default.
#
# NOTE: uses `has()`, not jq's `//` alternative operator — `.features[$key] //
# empty` wrongly yields empty when the value is literally `false` (jq treats
# false as empty), which made a disabled feature read back as its default. The
# sed fallback uses `sed -E` (extended regex) so `(true|false)` alternation also
# works under macOS's BSD sed, where a basic-regex `\|` matches nothing.
cm_data_bool() {
    local json="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$json" | jq -r --arg key "$key" '
            if has($key) then .[$key]
            elif (.features? // {} | has($key)) then .features[$key]
            else empty end'
    else
        printf '%s\n' "$json" |
            sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*(true|false).*/\1/p" |
            tail -1
    fi
}

# cm_toml_string FILE KEY — read a `key = "value"` line from a chezmoi.toml.
# The last-resort reader when chezmoi itself isn't on PATH yet.
cm_toml_string() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$file" | tail -1
}

# cm_toml_bool FILE KEY — read a `key = true|false` line from a chezmoi.toml.
# ERE (`sed -E`) so the alternation works under macOS's BSD sed too.
cm_toml_bool() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*\$/\1/p" "$file" | tail -1
}
# @inline-end
