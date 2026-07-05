#!/usr/bin/env bash
# wizard.sh — plain-text first-run setup wizard.
#
# chezmoi's own promptChoice/promptMultichoice template functions render an
# interactive TUI picker (the charmbracelet/huh library) that reads /dev/tty in
# raw mode. That picker is unreliable outside a "perfect" interactive terminal:
# under `curl | bash`, inside chezreset, or over some SSH/terminal combos it
# fails to register arrow-key navigation and just confirms the highlighted
# default. See docs/lifecycle.md.
#
# This wizard sidesteps the picker entirely: it asks each question with plain
# `read` from /dev/tty (numbered menus, typed answers, number-toggle multi-select
# — all of which work in ANY terminal) and then feeds the answers to chezmoi via
# its non-interactive flags:
#     chezmoi init --apply --prompt \
#         --promptString  "<message>=<value>"   (name, email, signing key)
#         --promptChoice  "<message>=<value>"   (profile, signing mode)
#         --promptMultichoice "<message>=a/b/c" (modules; items joined with '/')
# The flag KEY is each prompt's message text, so those messages are extracted
# from .chezmoi.toml.tmpl at runtime (single source of truth — no drift). The
# module catalog + per-profile defaults come from .chezmoidata/modules.toml.
#
# Kept POSIX-ish and bash-3.2 compatible (no associative arrays): a fresh Mac has
# only the system bash 3.2 until Homebrew installs a newer one.
#
# Usage:   bash scripts/wizard.sh [extra chezmoi-init args...]
# Env:     DOTFILES_DIR      override the chezmoi source dir (default: repo root)
#          DRY_RUN=1         print the resulting `chezmoi init` command, don't run
#          WIZARD_LIB_ONLY=1 source the helpers only; skip the interactive run
# No TTY (CI/containers): falls back to `chezmoi init --apply --promptDefaults`.

set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$_DIR/.." && pwd)"
# SOURCE_DIR is the repo root; chezmoi descends into src/ itself via .chezmoiroot
# (so `chezmoi init --source="$SOURCE_DIR"` is correct). The template + module
# data live under src/, chezmoi's actual source dir.
SOURCE_DIR="${DOTFILES_DIR:-$ROOT}"
TMPL="$ROOT/src/.chezmoi.toml.tmpl"
MODULES_TOML="$ROOT/src/.chezmoidata/modules.toml"

# shellcheck source=lib/log.sh
. "$_DIR/lib/log.sh"
# shellcheck source=lib/chezmoi-data.sh
. "$_DIR/lib/chezmoi-data.sh"
ui_init_logging

[ -f "$TMPL" ] || {
    fail "cannot find $TMPL — run this from inside the dotfiles repo"
    exit 1
}

# run_chezmoi — exec `chezmoi init` with the assembled args, or (DRY_RUN) print
# the exact command it would run and exit, so the wizard's answer-gathering can be
# exercised in tests without touching $HOME.
run_chezmoi() {
    if [ "$DRY_RUN" = "1" ]; then
        printf 'chezmoi init'
        printf ' %q' "$@"
        printf '\n'
        exit 0
    fi
    exec chezmoi init "$@"
}

# ─── Read the wizard's questions from the source of truth ────────────────────
# prompt_msg KEY — the message string chezmoi shows for a prompt*Once data KEY.
# It is also the flag key we pass back, so reading it here keeps the two in sync.
prompt_msg() {
    sed -nE "s/.*prompt(String|Choice|Multichoice)Once \. \"$1\"[[:space:]]+\"([^\"]*)\".*/\2/p" \
        "$TMPL" | head -n1
}

# prompt_choices KEY — the (list "a" "b" ...) options for a promptChoiceOnce KEY.
prompt_choices() {
    sed -nE "s/.*promptChoiceOnce \. \"$1\"[[:space:]]+\"[^\"]*\"[[:space:]]+\(list ([^)]*)\).*/\1/p" \
        "$TMPL" | head -n1 | grep -oE '"[^"]+"' | tr -d '"'
}

# profile_defaults PROFILE — space-separated default module keys for a profile.
profile_defaults() {
    awk -F' *= *' -v p="$1" '
        /^\[profileDefaults\]/ {f=1; next}
        /^\[/                  {f=0}
        f && $1==p             {v=$2; gsub(/[][",]/,"",v); print v; exit}
    ' "$MODULES_TOML"
}

# existing_modules — the modules already chosen (jq-optional; empty without jq).
# Reads DATA_JSON, set in the runtime section before this is called.
existing_modules() {
    command -v jq >/dev/null 2>&1 || return 0
    printf '%s' "${DATA_JSON:-}" | jq -r '.modules[]? // empty' 2>/dev/null | tr '\n' ' '
}

# ─── Prompt helpers (all I/O on /dev/tty; the answer goes to stdout) ──────────
ask_string() { # message default → echoes answer
    local msg="$1" def="${2:-}" ans
    if [ -n "$def" ]; then
        printf '%s [%s]: ' "$msg" "$def" >/dev/tty
    else
        printf '%s: ' "$msg" >/dev/tty
    fi
    IFS= read -r ans </dev/tty || ans=""
    [ -n "$ans" ] || ans="$def"
    printf '%s' "$ans"
}

ask_choice() { # message default opt1 opt2 ... → echoes chosen option
    local msg="$1" def="$2"
    shift 2
    local opts=("$@") i sel mark
    printf '\n%s:\n' "$msg" >/dev/tty
    for i in "${!opts[@]}"; do
        mark="  "
        [ "${opts[$i]}" = "$def" ] && mark=" *"
        printf '  %s %d) %s\n' "$mark" "$((i + 1))" "${opts[$i]}" >/dev/tty
    done
    while :; do
        printf 'choose a number or name [%s]: ' "$def" >/dev/tty
        IFS= read -r sel </dev/tty || sel=""
        [ -n "$sel" ] || {
            printf '%s' "$def"
            return
        }
        if printf '%s' "$sel" | grep -qE '^[0-9]+$' &&
            [ "$sel" -ge 1 ] && [ "$sel" -le "${#opts[@]}" ]; then
            printf '%s' "${opts[$((sel - 1))]}"
            return
        fi
        for i in "${opts[@]}"; do
            [ "$i" = "$sel" ] && {
                printf '%s' "$i"
                return
            }
        done
        printf '  not a valid choice\n' >/dev/tty
    done
}

select_modules() { # default-selected keys... → echoes chosen keys (catalog order)
    # bash 3.2 (macOS default, and all a fresh Mac has before Homebrew) lacks
    # associative arrays, so track selection in an indexed 0/1 flag array that
    # runs parallel to MOD_KEYS.
    local i j k mark line tok out
    local on=()
    for i in "${!MOD_KEYS[@]}"; do on[$i]=0; done
    for k in "$@"; do
        for i in "${!MOD_KEYS[@]}"; do
            [ "${MOD_KEYS[$i]}" = "$k" ] && on[$i]=1
        done
    done
    while :; do
        printf '\n%s — type numbers to toggle (e.g. 1,3,5), Enter to accept:\n' \
            "$(prompt_msg modules)" >/dev/tty
        for i in "${!MOD_KEYS[@]}"; do
            mark="[ ]"
            [ "${on[$i]}" = "1" ] && mark="[x]"
            printf '  %s %2d) %-14s %s\n' \
                "$mark" "$((i + 1))" "${MOD_KEYS[$i]}" "${MOD_LABELS[$i]}" >/dev/tty
        done
        printf 'toggle> ' >/dev/tty
        IFS= read -r line </dev/tty || line=""
        [ -n "$line" ] || break
        for tok in ${line//,/ }; do
            if printf '%s' "$tok" | grep -qE '^[0-9]+$' &&
                [ "$tok" -ge 1 ] && [ "$tok" -le "${#MOD_KEYS[@]}" ]; then
                j=$((tok - 1))
                if [ "${on[$j]}" = "1" ]; then on[$j]=0; else on[$j]=1; fi
            fi
        done
    done
    out=()
    for i in "${!MOD_KEYS[@]}"; do
        [ "${on[$i]}" = "1" ] && out+=("${MOD_KEYS[$i]}")
    done
    # ${out[*]:-} guards the empty case: bash 3.2 under `set -u` errors on a bare
    # empty-array expansion (minimal profile / everything deselected).
    printf '%s' "${out[*]:-}"
}

# ─── Module catalog (keys + labels), read once at load ───────────────────────
MOD_KEYS=() MOD_LABELS=()
while IFS=$'\t' read -r _k _v; do
    [ -n "$_k" ] || continue
    MOD_KEYS+=("$_k")
    MOD_LABELS+=("$_v")
done < <(awk -F' *= *' '
    /^\[moduleCatalog\]/ {f=1; next}
    /^\[/               {f=0}
    f && NF>1           {v=$2; gsub(/"/,"",v); print $1 "\t" v}
' "$MODULES_TOML")

[ "${#MOD_KEYS[@]}" -gt 0 ] || {
    fail "no modules found in $MODULES_TOML"
    exit 1
}

# Sourced for its helpers only (tests) — stop before any prompting or apply.
[ "${WIZARD_LIB_ONLY:-0}" = "1" ] && return 0

# ─── Non-interactive fallback ────────────────────────────────────────────────
# No controlling terminal → we can't ask anything. Let chezmoi apply its own
# template defaults so first-boot automation still converges instead of hanging.
if [ ! -r /dev/tty ]; then
    warn "no terminal detected — accepting default answers (--promptDefaults)"
    run_chezmoi --apply --promptDefaults --source="$SOURCE_DIR" "$@"
fi

# ─── Current answers become the defaults (nice on a chezreset re-run) ─────────
DATA_JSON="$(cm_data_json)"
def_name="$(cm_data_string "$DATA_JSON" name)"
def_email="$(cm_data_string "$DATA_JSON" email)"
def_profile="$(cm_data_string "$DATA_JSON" profile)"
def_signing="$(cm_data_string "$DATA_JSON" signingMode)"
def_signkey="$(cm_data_string "$DATA_JSON" signingKey)"
[ -n "$def_profile" ] || def_profile="personal"
[ -n "$def_signing" ] || def_signing="1password"

# ─── Ask ─────────────────────────────────────────────────────────────────────
printf '%s\n' "$BOX_TOP" >/dev/tty
say "dotfiles setup — answer a few questions, then chezmoi applies." >/dev/tty
printf '%s\n' "$BOX_BOTTOM" >/dev/tty

name="$(ask_string "$(prompt_msg name)" "$def_name")"
email="$(ask_string "$(prompt_msg email)" "$def_email")"

# shellcheck disable=SC2046  # word-splitting of the choice list is intentional
profile="$(ask_choice "$(prompt_msg profile)" "$def_profile" $(prompt_choices profile))"

# Default module selection: keep the current picks only when the profile is
# unchanged (a nice re-run); switching profile resets to that profile's defaults
# so a personal→minimal switch actually starts clean.
existing="$(existing_modules)"
if [ -n "$existing" ] && [ "$profile" = "$def_profile" ]; then
    mod_default="$existing"
else
    mod_default="$(profile_defaults "$profile")"
fi
# shellcheck disable=SC2086  # mod_default is a space-separated key list
modules="$(select_modules $mod_default)"

# shellcheck disable=SC2046
signingMode="$(ask_choice "$(prompt_msg signingMode)" "$def_signing" $(prompt_choices signingMode))"
signingKey=""
if [ "$signingMode" != "off" ]; then
    signingKey="$(ask_string "$(prompt_msg signingKey)" "$def_signkey")"
fi

# ─── Confirm ─────────────────────────────────────────────────────────────────
hr >/dev/tty
say "Summary:" >/dev/tty
dim "  name     $name" >/dev/tty
dim "  email    $email" >/dev/tty
dim "  profile  $profile" >/dev/tty
dim "  signing  $signingMode${signingKey:+ ($signingKey)}" >/dev/tty
dim "  modules  ${modules:-<none>}" >/dev/tty
printf 'Apply this setup? [Y/n] ' >/dev/tty
IFS= read -r reply </dev/tty || reply=""
case "$reply" in
    n | N | no | NO)
        info "aborted — nothing changed"
        exit 0
        ;;
esac

# ─── Hand off to chezmoi with the answers as flags (no TUI) ───────────────────
mods_slash="$(printf '%s' "$modules" | tr ' ' '/')"
init_flags=(
    --apply --prompt --source="$SOURCE_DIR"
    --promptString "$(prompt_msg name)=$name"
    --promptString "$(prompt_msg email)=$email"
    --promptChoice "$(prompt_msg profile)=$profile"
    --promptChoice "$(prompt_msg signingMode)=$signingMode"
    --promptMultichoice "$(prompt_msg modules)=$mods_slash"
)
if [ "$signingMode" != "off" ]; then
    init_flags+=(--promptString "$(prompt_msg signingKey)=$signingKey")
fi

run_chezmoi "${init_flags[@]}" "$@"
