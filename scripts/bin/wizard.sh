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
# its non-interactive flags.
#
# Progressive enhancement: when `gum` is installed AND we're on a real terminal,
# the choice/multi-select/input prompts upgrade to gum's arrow-key + space-toggle
# pickers (with the current selection pre-checked). gum is the CLI of the SAME
# charmbracelet engine as chezmoi's flaky embedded picker, so it's used ONLY here
# — on interactive re-runs, always behind the plain-text fallback below, and never
# at first-boot (gum isn't installed until Homebrew runs). Force the plain path
# with WIZARD_NO_GUM=1. The answers still go to chezmoi via the same flags:
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
# Usage:   bash scripts/bin/wizard.sh [extra chezmoi-init args...]
# Env:     DOTFILES_DIR      override the chezmoi source dir (default: repo root)
#          DRY_RUN=1         print the resulting `chezmoi init` command, don't run
#          WIZARD_NO_GUM=1   skip the gum picker (use the bash TUI / numbered menu)
#          WIZARD_NO_TUI=1   skip the bash arrow-key picker too (numbered menu only)
#          WIZARD_LIB_ONLY=1 source the helpers only; skip the interactive run
# No TTY (CI/containers): falls back to `chezmoi init --apply --promptDefaults`.

set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# This script lives at scripts/bin/, so the repo root is two levels up.
ROOT="$(cd "$_DIR/../.." && pwd)"
# SOURCE_DIR is the repo root; chezmoi descends into src/ itself via .chezmoiroot
# (so `chezmoi init --source="$SOURCE_DIR"` is correct). The template + module
# data live under src/, chezmoi's actual source dir.
SOURCE_DIR="${DOTFILES_DIR:-$ROOT}"
TMPL="$ROOT/src/.chezmoi.toml.tmpl"
MODULES_TOML="$ROOT/src/.chezmoidata/modules.toml"

# shellcheck source=../lib/log.sh
. "$_DIR/../lib/log.sh"
# shellcheck source=../lib/chezmoi-data.sh
. "$_DIR/../lib/chezmoi-data.sh"
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
# Three tiers of interactivity, most→least capable, each gated by a predicate:
#   1. gum        — installed + on PATH (re-runs after first install)
#   2. bash TUI   — a capable terminal but no gum (the first-boot case: pure
#                   bash 3.2 arrow/space picker, works before Homebrew exists)
#   3. numbered   — anything else (dumb/non-ANSI terminal): type numbers to pick
# The tiers degrade cleanly: gum → use_gum, TUI → use_tui, else the numbered
# menus below. So a fresh Mac's very first `install.sh` run still gets arrow/space
# selection with no dependency, and a terminal that can't do it falls all the way
# through to the numbered menu.

# use_gum — gum path: installed and not disabled. (The wizard has already
# guaranteed /dev/tty; first-boot never reaches here with gum, as Homebrew
# hasn't run yet — that's the bash-TUI tier's job.)
use_gum() { [ "${WIZARD_NO_GUM:-0}" != "1" ] && command -v gum >/dev/null 2>&1; }

# use_tui — pure-bash arrow/space picker path: an interactive, non-dumb terminal
# and not disabled. Gated OUT for TERM=dumb / no readable-writable /dev/tty /
# WIZARD_NO_TUI=1, so a degraded terminal cleanly falls through to the numbered
# menu. The picker also accepts number keys, so even if a terminal silently
# swallows arrow escapes the user can still toggle by digit.
use_tui() {
    [ "${WIZARD_NO_TUI:-0}" != "1" ] || return 1
    [ "${TERM:-dumb}" != "dumb" ] || return 1
    [ -r /dev/tty ] && [ -w /dev/tty ]
}

# _tui_read_key — read one keypress from /dev/tty; echo a normalized token:
# UP DOWN SPACE ENTER, a bare digit, or the raw char. Arrow keys arrive as the
# escape burst ESC [ A/B; we read the 2-byte tail with an integer timeout so a
# real arrow returns instantly (bytes already buffered) while a lone ESC press
# doesn't hang. bash-3.2 safe: `read -t` takes integer seconds (no fractional).
_tui_read_key() {
    local k rest
    IFS= read -rsn1 k </dev/tty || {
        printf 'ENTER'
        return
    }
    case "$k" in
        '' | $'\n' | $'\r') printf 'ENTER' ;; # Enter: empty under -n1, or CR/LF
        ' ') printf 'SPACE' ;;
        $'\x1b')
            IFS= read -rsn2 -t 1 rest </dev/tty || rest=''
            case "$rest" in
                '[A') printf 'UP' ;;
                '[B') printf 'DOWN' ;;
                *) printf 'ESC' ;;
            esac
            ;;
        k | K) printf 'UP' ;; # vi-style, and a fallback if arrows don't register
        j | J) printf 'DOWN' ;;
        *) printf '%s' "$k" ;; # digits and everything else, verbatim
    esac
}

# _tui_choose — single-select picker. message def opt... → echoes chosen option.
_tui_choose() {
    local msg="$1" def="$2"
    shift 2
    local opts=("$@") n=${#opts[@]} cur=0 i key arrow drawn=0
    for i in "${!opts[@]}"; do [ "${opts[$i]}" = "$def" ] && cur=$i; done
    {
        printf '\n%s\n' "$msg"
        printf '  ↑/↓ or j/k move · 1-%d picks by number · Enter selects\n\n' "$n"
    } >/dev/tty
    while :; do
        [ "$drawn" = 1 ] && printf '\033[%dA' "$n" >/dev/tty
        for i in "${!opts[@]}"; do
            arrow='  '
            [ "$i" = "$cur" ] && arrow='❯ '
            printf '\033[K%s%s\n' "$arrow" "${opts[$i]}" >/dev/tty
        done
        drawn=1
        key="$(_tui_read_key)"
        case "$key" in
            UP) cur=$(((cur - 1 + n) % n)) ;;
            DOWN) cur=$(((cur + 1) % n)) ;;
            ENTER) break ;;
            [1-9]) [ "$key" -le "$n" ] && {
                cur=$((key - 1))
                break
            } ;;
            *) : ;;
        esac
    done
    printf '%s' "${opts[$cur]}"
}

# _tui_multiselect — module checkbox picker over MOD_KEYS/MOD_LABELS.
# default-selected keys... → echoes chosen keys (catalog order).
_tui_multiselect() {
    local n=${#MOD_KEYS[@]} cur=0 i key mark arrow drawn=0 d idx
    local on=() out=()
    for i in "${!MOD_KEYS[@]}"; do on[$i]=0; done
    for d in "$@"; do
        for i in "${!MOD_KEYS[@]}"; do
            [ "${MOD_KEYS[$i]}" = "$d" ] && on[$i]=1
        done
    done
    {
        printf '\n%s\n' "$(prompt_msg modules)"
        printf '  ↑/↓ or j/k move · space toggles · 1-%d toggles by number · Enter confirms\n\n' "$n"
    } >/dev/tty
    while :; do
        [ "$drawn" = 1 ] && printf '\033[%dA' "$n" >/dev/tty
        for i in "${!MOD_KEYS[@]}"; do
            mark='[ ]'
            [ "${on[$i]}" = "1" ] && mark='[x]'
            arrow='  '
            [ "$i" = "$cur" ] && arrow='❯ '
            printf '\033[K%s%s %-13s %s\n' \
                "$arrow" "$mark" "${MOD_KEYS[$i]}" "${MOD_LABELS[$i]}" >/dev/tty
        done
        drawn=1
        key="$(_tui_read_key)"
        case "$key" in
            UP) cur=$(((cur - 1 + n) % n)) ;;
            DOWN) cur=$(((cur + 1) % n)) ;;
            SPACE) if [ "${on[$cur]}" = "1" ]; then on[$cur]=0; else on[$cur]=1; fi ;;
            ENTER) break ;;
            [1-9])
                idx=$((key - 1))
                [ "$idx" -lt "$n" ] && {
                    if [ "${on[$idx]}" = "1" ]; then on[$idx]=0; else on[$idx]=1; fi
                    cur=$idx
                }
                ;;
            *) : ;;
        esac
    done
    for i in "${!MOD_KEYS[@]}"; do
        [ "${on[$i]}" = "1" ] && out+=("${MOD_KEYS[$i]}")
    done
    printf '%s' "${out[*]:-}"
}

ask_string() { # message default → echoes answer
    local msg="$1" def="${2:-}" ans
    if use_gum; then
        # gum input: default pre-filled + editable, arrow/emacs line editing.
        ans="$(gum input --prompt "$msg: " --value "$def")" || ans="$def"
        [ -n "$ans" ] || ans="$def"
        printf '%s' "$ans"
        return
    fi
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
    if use_gum; then
        # gum choose (single-select): arrows move, enter picks; default pre-highlighted.
        local picked
        local -a ga=(--header "$msg")
        [ -n "$def" ] && ga+=(--selected "$def")
        picked="$(gum choose "${ga[@]}" "${opts[@]}")" || picked="$def"
        [ -n "$picked" ] || picked="$def"
        printf '%s' "$picked"
        return
    fi
    if use_tui; then
        _tui_choose "$msg" "$def" "${opts[@]}"
        return
    fi
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

# mod_display INDEX — the "key  label" line shown for a module in the gum picker.
# gum's --selected takes a COMMA-separated list, and some labels contain commas
# (jvmStack, cloudAuth), so commas are swapped for '·' here; results are mapped
# back to keys by exact-line match, not by parsing. Kept a function so a test can
# assert the comma-free invariant.
mod_display() { # index → display line
    printf '%-13s %s' "${MOD_KEYS[$1]}" "${MOD_LABELS[$1]//,/·}"
}

select_modules_gum() { # default-selected keys... → echoes chosen keys (catalog order)
    local i d chosen
    local -a display=() selected=() gargs
    for i in "${!MOD_KEYS[@]}"; do display[$i]="$(mod_display "$i")"; done
    # Pre-check the incoming default keys (their display lines).
    for d in "$@"; do
        for i in "${!MOD_KEYS[@]}"; do
            [ "${MOD_KEYS[$i]}" = "$d" ] && selected+=("${display[$i]}")
        done
    done
    gargs=(--no-limit --header "$(prompt_msg modules) (space toggles, enter confirms)")
    if [ "${#selected[@]}" -gt 0 ]; then
        local sel_csv
        sel_csv="$(
            IFS=,
            printf '%s' "${selected[*]}"
        )"
        gargs+=(--selected "$sel_csv")
    fi
    # gum reads options from stdin and drives the TUI on the controlling terminal.
    chosen="$(printf '%s\n' "${display[@]}" | gum choose "${gargs[@]}")" || chosen=""
    # Map chosen lines back to keys, preserving catalog order (exact match; safe
    # against glob/regex chars in labels).
    local out=()
    for i in "${!MOD_KEYS[@]}"; do
        if printf '%s\n' "$chosen" | grep -Fxq -- "${display[$i]}"; then
            out+=("${MOD_KEYS[$i]}")
        fi
    done
    printf '%s' "${out[*]:-}"
}

select_modules() { # default-selected keys... → echoes chosen keys (catalog order)
    if use_gum; then
        select_modules_gum "$@"
        return
    fi
    if use_tui; then
        _tui_multiselect "$@"
        return
    fi
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
