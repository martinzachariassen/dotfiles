#!/usr/bin/env bash
# signing.sh — set the git commit-signing key on a machine that deferred it.
# Backs the `chezsign` verb. Solves the fresh-Mac chicken-and-egg: the key lives
# in 1Password, which isn't installed until after the wizard has already run.
# Re-asks nothing else — profile, modules and identity are replayed as-is.
# Env: DRY_RUN=1 print the chezmoi command instead of running it.
#      YES=1 take the single offered key without prompting.
#      SKIP_SIGNTEST=1 skip the closing smoke test.

set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${YES:-0}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$_DIR/../.." && pwd)"
# Repo root, not src/: chezmoi descends into src/ itself via .chezmoiroot.
SOURCE_DIR="${DOTFILES_DIR:-$ROOT}"
TMPL="$ROOT/src/.chezmoi.toml.tmpl"

if [ ! -r "$_DIR/../../core/ui.sh" ]; then
    printf 'chezsign: missing %s\n' "$_DIR/../../core/ui.sh" >&2
    exit 1
fi
# shellcheck source=../../core/ui.sh
. "$_DIR/../../core/ui.sh"
# shellcheck source=../../core/chezmoi-data.sh
. "$_DIR/../../core/chezmoi-data.sh"
# shellcheck source=../../core/prompt-meta.sh
. "$_DIR/../../core/prompt-meta.sh"
# shellcheck source=lib.sh
. "$_DIR/lib.sh"
ui_init_logging

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

usage() {
    echo "usage: chezsign [KEY]"
    echo "  (no arg)   pick a key from the SSH agent, or paste one"
    echo "  KEY        set this public key line non-interactively"
    echo
    echo "Sets only the git signing key. Profile, modules and identity are kept."
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac
EXPLICIT_KEY="${1:-}"

# normalize_key — reduce a public key line to "<type> <base64>". Agents append a
# comment ("... SSH Key") and allowed_signers is "<email> <key>" per line, so a
# comment would land mid-line; stripping it also keeps the idempotence check honest.
normalize_key() {
    awk '{ if (NF >= 2) print $1, $2; else print }'
}

# agent_keys — public key lines the running SSH agent will sign with. Prefers
# 1Password's socket, falls back to whatever $SSH_AUTH_SOCK points at.
agent_keys() {
    local sock="${CHEZSIGN_AGENT_SOCK:-$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock}"
    [ -S "$sock" ] || sock="${SSH_AUTH_SOCK:-}"
    [ -n "$sock" ] && [ -S "$sock" ] || return 0
    SSH_AUTH_SOCK="$sock" ssh-add -L 2>/dev/null | grep -E '^(ssh|ecdsa)-' | normalize_key || true
}

DATA_JSON="$(cm_data_json)"
name="$(cm_data_string "$DATA_JSON" name)"
email="$(cm_data_string "$DATA_JSON" email)"
profile="$(cm_data_string "$DATA_JSON" profile)"
mode="$(cm_data_string "$DATA_JSON" signingMode)"
current_key="$(cm_data_string "$DATA_JSON" signingKey)"
[ -n "$mode" ] || mode="1password"

if [ "$mode" = "off" ]; then
    warn "signing is set to \"off\" for this machine, so there's no key to set."
    info "turn it on with: chezsetup --reset  (then pick 1password or ssh-key)"
    exit 0
fi

say "Signing mode  $mode"
if [ -n "$current_key" ]; then
    say "Current key   $current_key"
else
    say "Current key   (not set — commits are unsigned)"
fi
echo

# --- choose the key ------------------------------------------------------
new_key=""
if [ -n "$EXPLICIT_KEY" ]; then
    new_key="$EXPLICIT_KEY"
else
    keys=()
    while IFS= read -r line; do
        [ -n "$line" ] && keys+=("$line")
    done <<<"$(agent_keys)"

    if [ "${#keys[@]}" -eq 0 ]; then
        warn "no SSH agent keys found."
        if [ "$mode" = "1password" ]; then
            info "open 1Password → Settings → Developer → enable the SSH agent, then re-run."
        fi
        info "or paste the public key line directly: chezsign \"ssh-ed25519 AAAA... comment\""
        exit 1
    fi

    if [ "${#keys[@]}" -eq 1 ] && [ "$ASSUME_YES" = "1" ]; then
        new_key="${keys[0]}"
    else
        say "Keys offered by the agent:"
        i=1
        for k in "${keys[@]}"; do
            printf '  %d) %s\n' "$i" "$k"
            i=$((i + 1))
        done
        printf '  %d) paste a key manually\n' "$i"
        echo
        printf 'Choice [1]: ' >/dev/tty
        IFS= read -r choice </dev/tty || choice=""
        [ -n "$choice" ] || choice=1
        if [ "$choice" = "$i" ]; then
            printf 'Public key line: ' >/dev/tty
            IFS= read -r new_key </dev/tty || new_key=""
        elif [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -lt "$i" ]; then
            new_key="${keys[$((choice - 1))]}"
        else
            fail "not a valid choice — nothing changed"
            exit 1
        fi
    fi
fi

[ -n "$new_key" ] || {
    fail "empty key — nothing changed"
    exit 1
}
new_key="$(printf '%s\n' "$new_key" | normalize_key)"

if [ "$new_key" = "$current_key" ]; then
    ok "that key is already configured — nothing to change."
    exit 0
fi

# --- write it back -------------------------------------------------------
# chezmoi keys its non-interactive flags by prompt message, and promptStringOnce
# ignores a saved answer only under --prompt, so every answer is replayed here.
mods_slash=""
if command -v jq >/dev/null 2>&1; then
    mods_slash="$(printf '%s' "$DATA_JSON" | jq -r '(.modules // []) | join("/")')"
else
    warn "jq not found — module selection cannot be replayed; chezmoi will re-ask it."
fi

init_flags=(
    --apply --force --prompt --source="$SOURCE_DIR"
    --promptString "$(prompt_msg name)=$name"
    --promptString "$(prompt_msg email)=$email"
    --promptChoice "$(prompt_msg profile)=$profile"
    --promptChoice "$(prompt_msg signingMode)=$mode"
    --promptString "$(prompt_msg signingKey)=$new_key"
    --promptString "$(prompt_msg corpusRemote)=$(cm_data_string "$DATA_JSON" corpusRemote)"
)
[ -n "$mods_slash" ] && init_flags+=(--promptMultichoice "$(prompt_msg modules)=$mods_slash")

info "setting signing key → $new_key"
if [ "$DRY_RUN" = "1" ]; then
    printf 'chezmoi init'
    printf ' %q' "${init_flags[@]}"
    printf '\n'
    exit 0
fi
chezmoi init "${init_flags[@]}"

# --- prove it works ------------------------------------------------------
if [ "${SKIP_SIGNTEST:-0}" = "1" ]; then
    ok "signing key set."
    exit 0
fi
echo
if git_signing_smoke_test; then
    ok "signed commit succeeded — signing is live."
else
    fail "a signed commit still fails."
    if [ "$mode" = "1password" ]; then
        warn "check 1Password is unlocked and Settings → Developer → SSH agent is on."
    fi
    exit 1
fi
