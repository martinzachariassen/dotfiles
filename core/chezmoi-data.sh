#!/usr/bin/env bash
# chezmoi-data.sh — read chezmoi `[data]` values without a hard jq dependency (sed fallback). Missing keys echo "".
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

# cm_data_bool JSON KEY — bool from top level then `.features`; uses has(), not jq's `//` which treats false as empty.
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

# cm_has_module JSON MODULE — true when MODULE is in the `.modules` list.
cm_has_module() {
    local json="$1" module="$2"
    command -v jq >/dev/null 2>&1 || return 1
    printf '%s\n' "$json" | jq -e --arg m "$module" '(.modules // []) | index($m)' >/dev/null 2>&1
}
