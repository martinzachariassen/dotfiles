#!/usr/bin/env bash
# modules.sh — read and update THIS Mac's module selection.
#
# Shared by chezup (the "new modules since this Mac was set up" gate), wizard.sh
# and chezdistill --setup, so the three can't disagree about what the module
# list is or how it is written — the same reason scripts/lib/xcode.sh is shared
# between chezxcode and chezdoctor.
#
# Why the config file is edited line-by-line rather than re-running
# `chezmoi init`: init re-derives every saved answer, and these callers have to
# change exactly one key. That edit used to live only in distill.sh.

[ -n "${__DOTFILES_MODULES_SH:-}" ] && return 0
__DOTFILES_MODULES_SH=1

# modules_config_file — the generated chezmoi config these writers edit.
modules_config_file() {
    printf '%s\n' "${CHEZMOI_CONFIG_FILE:-$HOME/.config/chezmoi/chezmoi.toml}"
}

# _modules_json [JSON] — chezmoi data, fetched when not supplied. Needs jq.
_modules_json() {
    local json="${1:-}"
    command -v jq >/dev/null 2>&1 || return 1
    [ -n "$json" ] || json="$(chezmoi data --format=json 2>/dev/null)"
    [ -n "$json" ] || return 1
    printf '%s' "$json"
}

# modules_catalog [JSON] — every module key the repo offers, one per line.
modules_catalog() {
    local json
    json="$(_modules_json "${1:-}")" || return 1
    printf '%s' "$json" | jq -r '(.moduleCatalog // {}) | keys[]' 2>/dev/null
}

# modules_enabled [JSON] — modules selected on this Mac.
modules_enabled() {
    local json
    json="$(_modules_json "${1:-}")" || return 1
    printf '%s' "$json" | jq -r '(.modules // [])[]' 2>/dev/null
}

# modules_seen [JSON] — modules this Mac has been offered at least once.
# Absent on a config written before the key existed; that is the whole point of
# the default in .chezmoi.toml.tmpl, and here it simply reads as empty.
modules_seen() {
    local json
    json="$(_modules_json "${1:-}")" || return 1
    printf '%s' "$json" | jq -r '(.modulesSeen // [])[]' 2>/dev/null
}

# modules_label JSON KEY — the catalog description, for display.
modules_label() {
    local json
    json="$(_modules_json "${1:-}")" || return 1
    printf '%s' "$json" | jq -r --arg k "$2" \
        '(.moduleCatalog // {})[$k] // empty' 2>/dev/null
}

# modules_unseen [JSON] — catalog minus enabled minus seen, in catalog order.
# "Never asked about on this Mac", which is not the same as "not installed":
# a module deliberately declined is in `modulesSeen` and never offered again.
modules_unseen() {
    local json
    json="$(_modules_json "${1:-}")" || return 1
    printf '%s' "$json" | jq -r '
        ((.modules // []) + (.modulesSeen // [])) as $known
        | ((.moduleCatalog // {}) | keys)
        | map(select(. as $m | $known | index($m) | not))
        | .[]' 2>/dev/null
}

# modules_toml_array VALUE… — `["a", "b"]`, byte-identical to what
# .chezmoi.toml.tmpl renders, so an edit here and a later `chezmoi init` agree.
# Duplicates are dropped: callers build these lists by appending to whatever is
# already saved, and a module can legitimately appear in both halves.
modules_toml_array() {
    local out="" seen=" " v
    for v in "$@"; do
        case "$seen" in *" $v "*) continue ;; esac
        seen="$seen$v "
        out="${out:+$out, }\"$v\""
    done
    printf '[%s]' "$out"
}

# modules_write_list CFG KEY VALUE… — rewrite `KEY = [...]` in the chezmoi
# config, touching exactly that one line. When KEY is absent it is inserted
# after the `modules` line, which is the case on any Mac whose config was
# generated before the key existed. 0 = written · 1 = could not.
modules_write_list() {
    local cfg="$1" key="$2"
    shift 2
    local array hit n prefix indent new tmp

    [ -f "$cfg" ] && [ -w "$cfg" ] || return 1
    array="$(modules_toml_array "$@")"
    tmp="$cfg.modules.tmp"

    hit="$(grep -n "^[[:space:]]*${key}[[:space:]]*=" "$cfg" | head -1)"
    if [ -n "$hit" ]; then
        n="${hit%%:*}"
        # Keep everything up to the `=` so the generated file's column
        # alignment survives the edit.
        prefix="${hit#*:}"
        prefix="${prefix%%=*}"
        new="$prefix= $array"
        awk -v n="$n" -v repl="$new" 'NR == n { print repl; next } { print }' \
            "$cfg" >"$tmp" && mv "$tmp" "$cfg" && return 0
        rm -f "$tmp"
        return 1
    fi

    hit="$(grep -n '^[[:space:]]*modules[[:space:]]*=' "$cfg" | head -1)"
    [ -n "$hit" ] || return 1
    n="${hit%%:*}"
    indent="${hit#*:}"
    indent="${indent%%[![:space:]]*}"
    new="$indent$key = $array"
    awk -v n="$n" -v repl="$new" 'NR == n { print; print repl; next } { print }' \
        "$cfg" >"$tmp" && mv "$tmp" "$cfg" && return 0
    rm -f "$tmp"
    return 1
}
