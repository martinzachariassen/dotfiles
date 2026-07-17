#!/usr/bin/env bash
# chezmoi-data.sh — read chezmoi `[data]` values without a hard jq dependency.
# jq when present, sed fallback for a fresh Mac. Missing keys echo ""; callers
# apply defaults.
# shellcheck disable=SC2034,SC2329

[ -n "${__DOTFILES_CHEZMOI_DATA_SH:-}" ] && return 0
__DOTFILES_CHEZMOI_DATA_SH=1

cm_data_json() {
    chezmoi data --format=json 2>/dev/null || echo '{}'
}

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

# cm_data_bool JSON KEY — bool from top level then `.features`. Uses `has()`,
# not jq's `//`, which treats literal `false` as empty and returns the default.
# sed fallback uses ERE so `(true|false)` works under BSD sed.
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

# cm_toml_string FILE KEY — read `key = "value"`; last resort when chezmoi
# isn't on PATH yet.
cm_toml_string() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$file" | tail -1
}

# cm_toml_bool FILE KEY — read `key = true|false`. ERE for BSD sed.
cm_toml_bool() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*\$/\1/p" "$file" | tail -1
}
