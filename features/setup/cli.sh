#!/usr/bin/env bash
# cli.sh — plain-text first-run setup wizard (`chez setup`). Sidesteps chezmoi's flaky TUI
# picker: asks each question with plain `read` (bash-3.2 safe, works in any
# terminal), upgrades to gum when installed, then hands answers to chezmoi's
# non-interactive init flags. Prompt messages are read from .chezmoi.toml.tmpl
# and the module catalog from .chezmoidata/modules.toml so nothing drifts.

set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$_DIR/../.." && pwd)"
# Repo root, not src/: chezmoi descends into src/ itself via .chezmoiroot.
SOURCE_DIR="${DOTFILES_DIR:-$ROOT}"
TMPL="$ROOT/src/.chezmoi.toml.tmpl"
MODULES_TOML="$ROOT/src/.chezmoidata/modules.toml"

# log.sh is a committed sibling; fail loudly if a checkout is missing it.
if [ ! -r "$_DIR/../../core/ui.sh" ]; then
    printf 'wizard: missing %s\n' "$_DIR/../../core/ui.sh" >&2
    exit 1
fi
# shellcheck source=../../core/ui.sh
. "$_DIR/../../core/ui.sh"
# shellcheck source=../../core/chezmoi-data.sh
. "$_DIR/../../core/chezmoi-data.sh"
# shellcheck source=../../core/prompt-meta.sh
. "$_DIR/../../core/prompt-meta.sh"
ui_init_logging

# `read … || fallback` swallows an interrupted read and marches on, so trap
# Ctrl-C explicitly; restore the cursor (pickers can hide it) and exit 130.
on_interrupt() {
    printf '\033[?25h\n' >/dev/tty 2>/dev/null || true
    info "aborted — nothing changed" >/dev/tty 2>/dev/null || true
    exit 130
}
trap on_interrupt INT TERM

[ -f "$TMPL" ] || {
    fail "cannot find $TMPL — run this from inside the dotfiles repo"
    exit 1
}

# run_chezmoi — exec `chezmoi init`, or print it under DRY_RUN (for tests).
run_chezmoi() {
    if [ "$DRY_RUN" = "1" ]; then
        printf 'chezmoi init'
        printf ' %q' "$@"
        printf '\n'
        exit 0
    fi
    exec chezmoi init "$@"
}

# profile_defaults PROFILE — space-separated default module keys: (inherit ?
# base : []) ∪ extra, base first, de-duplicated.
profile_defaults() {
    local p="$1" inherits base extra out="" seen=" " tok

    inherits="$(awk -v p="$p" '
        /^\[profileDefaults\.inherit\]/ {f=1; next}
        /^\[/                           {f=0}
        f && $1==p {print $3; exit}
    ' "$MODULES_TOML")"

    # grep exits 1 on an empty array (personal/minimal have none); swallow it.
    base="$(awk '
        /^\[profileDefaults\]/ {f=1; next}
        /^\[/                  {f=0}
        f
    ' "$MODULES_TOML" | grep -oE '"[a-zA-Z]+"' | tr -d '"' || true)"

    extra="$(awk -v p="$p" '
        /^\[profileDefaults\.extra\]/ {f=1; next}
        /^\[/                         {f=0}
        f { if ($0 ~ "^[ \t]*" p "[ \t]*=") c=1; if (c) { print; if ($0 ~ /\]/) c=0 } }
    ' "$MODULES_TOML" | grep -oE '"[a-zA-Z]+"' | tr -d '"' || true)"

    [ "$inherits" = "false" ] && base=""
    for tok in $base $extra; do
        case "$seen" in *" $tok "*) continue ;; esac
        out="${out:+$out }$tok"
        seen="$seen$tok "
    done
    printf '%s\n' "$out"
}

# existing_modules — modules already chosen (empty without jq). Reads DATA_JSON.
existing_modules() {
    command -v jq >/dev/null 2>&1 || return 0
    printf '%s' "${DATA_JSON:-}" | jq -r '.modules[]? // empty' 2>/dev/null | tr '\n' ' '
}

# Prompt helpers: I/O on /dev/tty, answer on stdout. Three tiers, most→least
# capable: gum → bash TUI arrow/space picker → numbered menu (dumb terminal).

use_gum() { [ "${WIZARD_NO_GUM:-0}" != "1" ] && command -v gum >/dev/null 2>&1; }

# signing_agent_present — true when an SSH agent is already handing out keys, so
# "set the key now" is a realistic answer. False on a just-wiped Mac.
signing_agent_present() {
    local sock="${WIZARD_AGENT_SOCK:-$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock}"
    [ -S "$sock" ] || sock="${SSH_AUTH_SOCK:-}"
    [ -n "$sock" ] && [ -S "$sock" ] || return 1
    SSH_AUTH_SOCK="$sock" ssh-add -L >/dev/null 2>&1
}

# use_tui — pure-bash arrow/space picker; gated out for TERM=dumb / no rw /dev/tty.
use_tui() {
    [ "${WIZARD_NO_TUI:-0}" != "1" ] || return 1
    [ "${TERM:-dumb}" != "dumb" ] || return 1
    [ -r /dev/tty ] && [ -w /dev/tty ]
}

# _tui_read_key — read one keypress; echo UP/DOWN/SPACE/ENTER, a digit, or the
# raw char. Arrows arrive as ESC [ A/B; bash-3.2 `read -t` only takes whole
# seconds, so the tail read times out at 1s rather than hanging on a lone ESC.
_tui_read_key() {
    local k rest
    IFS= read -rsn1 k </dev/tty || {
        printf 'ENTER'
        return
    }
    case "$k" in
        '' | $'\n' | $'\r') printf 'ENTER' ;;
        ' ') printf 'SPACE' ;;
        $'\x1b')
            IFS= read -rsn2 -t 1 rest </dev/tty || rest=''
            case "$rest" in
                '[A') printf 'UP' ;;
                '[B') printf 'DOWN' ;;
                *) printf 'ESC' ;;
            esac
            ;;
        k | K) printf 'UP' ;; # vi-style fallback if arrows don't register
        j | J) printf 'DOWN' ;;
        *) printf '%s' "$k" ;;
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

# _tui_multiselect — module checkbox picker over MOD_KEYS/MOD_LABELS; default-
# selected keys... → echoes chosen keys (catalog order).
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

# mod_display INDEX — "key  label" for the gum picker; commas in labels are
# swapped for '·' since gum's --selected list is itself comma-separated.
mod_display() { # index → display line
    printf '%-13s %s' "${MOD_KEYS[$1]}" "${MOD_LABELS[$1]//,/·}"
}

select_modules_gum() { # default-selected keys... → echoes chosen keys (catalog order)
    local i d chosen
    local -a display=() selected=() gargs
    for i in "${!MOD_KEYS[@]}"; do display[$i]="$(mod_display "$i")"; done
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
    chosen="$(printf '%s\n' "${display[@]}" | gum choose "${gargs[@]}")" || chosen=""
    # Map chosen lines back to keys in catalog order (exact match, glob-safe).
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
    # bash 3.2 lacks associative arrays; track selection in a 0/1 flag array.
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
    # ${out[*]:-}: bash 3.2 under set -u errors on a bare empty-array expansion.
    printf '%s' "${out[*]:-}"
}

MOD_KEYS=() MOD_LABELS=()
while IFS=$'\t' read -r _k _v; do
    [ -n "$_k" ] || continue
    MOD_KEYS+=("$_k")
    MOD_LABELS+=("$_v")
done < <(awk -F' *= *' '
    /^\[moduleCatalog\]/  {f=1; next}
    /^\[/                 {f=0}
    f && $1 ~ /^[A-Za-z]/ {v=$2; gsub(/"/,"",v); print $1 "\t" v}
' "$MODULES_TOML")

[ "${#MOD_KEYS[@]}" -gt 0 ] || {
    fail "no modules found in $MODULES_TOML"
    exit 1
}

# Sourced for its helpers only (tests) — stop before any prompting or apply.
[ "${WIZARD_LIB_ONLY:-0}" = "1" ] && return 0

# No terminal → let chezmoi apply its template defaults so automation converges.
if [ ! -r /dev/tty ]; then
    warn "no terminal detected — accepting default answers (--promptDefaults)"
    run_chezmoi --apply --force --promptDefaults --source="$SOURCE_DIR" "$@"
fi

# Current answers become the defaults (nice on a `chez setup --reset` re-run).
DATA_JSON="$(cm_data_json)"
def_name="$(cm_data_string "$DATA_JSON" name)"
def_email="$(cm_data_string "$DATA_JSON" email)"
def_profile="$(cm_data_string "$DATA_JSON" profile)"
def_signing="$(cm_data_string "$DATA_JSON" signingMode)"
def_signkey="$(cm_data_string "$DATA_JSON" signingKey)"
def_corpus="$(cm_data_string "$DATA_JSON" corpusRemote)"
[ -n "$def_profile" ] || def_profile="personal"
[ -n "$def_signing" ] || def_signing="1password"

printf '%s\n' "$BOX_TOP" >/dev/tty
say "Setup — 4 quick questions, then this Mac gets configured." >/dev/tty
printf '%s\n' "$BOX_BOTTOM" >/dev/tty
{
    echo
    explain \
        "Nothing is permanent: every answer is saved and can be changed later" \
        "with \`chez setup\`, and applying never uninstalls anything." \
        "" \
        "Press Enter to accept the value shown in [brackets]."
} >/dev/tty

# ask_step N TITLE WHY… — question header + why it is being asked.
QSTEP=0
QTOTAL=4
ask_step() {
    QSTEP=$((QSTEP + 1))
    _ask_header "$(printf '%s[%d/%d]%s' "$DIM" "$QSTEP" "$QTOTAL" "$RESET")" "$@"
}

# ask_sub — a follow-up to the current question; no number of its own.
ask_sub() { _ask_header "$(printf '%s   %s%s' "$DIM" "$SUB_MARK" "$RESET")" "$@"; }

_ask_header() {
    local lead="$1" title="$2"
    shift 2
    {
        echo
        printf '%s%s%s  %s %s%s%s\n' "$CYAN" "$NODE" "$RESET" "$lead" "$BOLD" "$title" "$RESET"
        explain "$@"
    } >/dev/tty
}

ask_step "Who you are" \
    "Goes into ~/.config/git/config as your commit author." \
    "Use your GitHub noreply address if you'd rather not publish a real one" \
    "(github.com → Settings → Emails → keep my email address private)." \
    "" \
    "Don't know it yet? Leave the email blank and run \`chez setup\` later;" \
    "until then git refuses to commit rather than guess an address."
name="$(ask_string "$(prompt_msg name)" "$def_name")"
email="$(ask_string "$(prompt_msg email)" "$def_email")"

# Say it at the moment it happens, not only in the summary. A blank email used
# to sail through and then author every commit as "Name <>" — invisible until
# someone noticed GitHub attributing nothing.
if [ -z "$email" ]; then
    {
        warn "no email set — git will refuse to commit until you add one."
        explain \
            "That is deliberate: the alternative is commits authored as" \
            "\"$name <>\", which GitHub cannot attribute and only a history" \
            "rewrite undoes." \
            "" \
            "Fix it any time with \`chez setup\` — it re-asks this one question." \
            "Your GitHub noreply address is on github.com → Settings → Emails."
    } >/dev/tty
fi

ask_step "Profile" \
    "Picks which set of packages this Mac installs." \
    "  personal   everything, including Swift/iOS tooling" \
    "  work       adds cloud CLIs (az, gcloud) instead" \
    "  minimal    the neutral base only — no extras"
# shellcheck disable=SC2046  # word-splitting of the choice list is intentional
profile="$(ask_choice "$(prompt_msg profile)" "$def_profile" $(prompt_choices profile))"

# Keep current picks only when the profile is unchanged; switching profile resets
# to that profile's defaults so the switch starts clean.
existing="$(existing_modules)"
if [ -n "$existing" ] && [ "$profile" = "$def_profile" ]; then
    mod_default="$existing"
else
    mod_default="$(profile_defaults "$profile")"
fi
ask_step "Optional modules" \
    "Extras on top of the profile — each one is independent." \
    "The defaults below are the usual pick for your profile; adjust if you like."
# shellcheck disable=SC2086  # mod_default is a space-separated key list
modules="$(select_modules $mod_default)"

# Only worth asking when the distiller is actually on. ask_sub, not ask_step, so
# QTOTAL stays honest: a numbered question that is sometimes skipped would make
# the header promise more questions than it asks (tests/setup-ux.bats).
corpusRemote="$def_corpus"
case " $modules " in
    *" claudeDistiller "*)
        ask_sub "Corpus backup (optional)" \
            "A private git repo the distiller pushes its corpus to so a new Mac inherits it." \
            "Leave blank to keep everything on this Mac — you can attach one later with:" \
            "  chez distill --remote <url>"
        printf '  %s[%s]%s ' "$DIM" "${def_corpus:-blank}" "$RESET"
        IFS= read -r corpusRemote </dev/tty || corpusRemote=""
        [ -n "$corpusRemote" ] || corpusRemote="$def_corpus"
        ;;
esac

ask_step "Commit signing" \
    "Signs your git commits so GitHub shows them as Verified." \
    "  1password  sign via the 1Password app's SSH agent" \
    "  ssh-key    sign with a plain SSH key you already have" \
    "  off        don't sign at all"
# shellcheck disable=SC2046
signingMode="$(ask_choice "$(prompt_msg signingMode)" "$def_signing" $(prompt_choices signingMode))"
signingKey=""
if [ "$signingMode" != "off" ]; then
    # Chicken-and-egg on a fresh Mac: the signing key lives in 1Password, which
    # Homebrew hasn't installed yet. Offer to defer rather than demand a paste;
    # default to whichever is actually possible right now.
    # Kept short: ask_choice echoes the chosen option back as the default in the
    # "[...]" prompt, and a sentence-long label makes that line unreadable. The
    # explanation lives in the ask_sub block above instead.
    key_now="now"
    key_later="later"
    key_when="$key_now"
    if [ -z "$def_signkey" ]; then
        key_default="$key_later"
        signing_agent_present && key_default="$key_now"
        ask_sub "Signing key" \
            "On a fresh Mac this key is still inside 1Password, which Homebrew" \
            "hasn't installed yet — so \"later\" is the normal answer here." \
            "Commits just stay unsigned until you run \`chez sign\`."
        key_when="$(ask_choice "When do you want to set the signing key?" "$key_default" "$key_now" "$key_later")"
    fi
    if [ "$key_when" = "$key_now" ]; then
        signingKey="$(ask_string "$(prompt_msg signingKey)" "$def_signkey")"
    fi
fi

{
    echo
    printf '%s%s%s  %sYour setup%s\n' "$CYAN" "$NODE" "$RESET" "$BOLD" "$RESET"
} >/dev/tty
dim "  name     $name" >/dev/tty
# Never print an empty value as if it were an answer — that blank line is
# exactly what made a missing email easy to walk past on a real install.
dim "  email    ${email:-<not set — run \`chez setup\` to add one>}" >/dev/tty
dim "  profile  $profile" >/dev/tty
if [ "$signingMode" != "off" ] && [ -z "$signingKey" ]; then
    dim "  signing  $signingMode (key deferred — run \`chez sign\` later)" >/dev/tty
else
    dim "  signing  $signingMode${signingKey:+ ($signingKey)}" >/dev/tty
fi
dim "  modules  ${modules:-<none>}" >/dev/tty
{
    echo
    explain \
        "Saying yes will:" \
        "  · write these config files into your home folder" \
        "  · install the packages your profile declares (the slow part)" \
        "  · apply macOS defaults, if you kept that module" \
        "" \
        "It never uninstalls anything, and it is safe to re-run." \
        "Expect 10-20 min on a fresh Mac; you may be asked for your password."
    echo
} >/dev/tty
printf 'Apply this setup? [Y/n] ' >/dev/tty
IFS= read -r reply </dev/tty || reply=""
case "$reply" in
    n | N | no | NO)
        info "aborted — nothing changed"
        exit 0
        ;;
esac

mods_slash="$(printf '%s' "$modules" | tr ' ' '/')"
# --force: without it chezmoi stops on every target that changed since it last
# wrote it and asks diff/overwrite/all-overwrite/skip/quit. The single
# "Apply this setup? [Y/n]" above is the confirmation gate; from there the
# apply runs to completion. (`force` is flag-only — there is no config key.)
init_flags=(
    --apply --force --prompt --source="$SOURCE_DIR"
    --promptString "$(prompt_msg name)=$name"
    --promptString "$(prompt_msg email)=$email"
    --promptChoice "$(prompt_msg profile)=$profile"
    --promptChoice "$(prompt_msg signingMode)=$signingMode"
    --promptMultichoice "$(prompt_msg modules)=$mods_slash"
    --promptString "$(prompt_msg corpusRemote)=$corpusRemote"
)
if [ "$signingMode" != "off" ]; then
    init_flags+=(--promptString "$(prompt_msg signingKey)=$signingKey")
fi

{
    echo
    info "applying — chezmoi takes over from here"
    explain "Progress prints per step; nothing else is needed from you unless prompted."
} >/dev/tty

run_chezmoi "${init_flags[@]}" "$@"
