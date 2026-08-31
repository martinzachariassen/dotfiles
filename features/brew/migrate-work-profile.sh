#!/usr/bin/env bash
# migrate-work-profile.sh — one-time: retire the `profile` key from this Mac's
# chezmoi config, keeping every package the old `work` tier used to declare.
#
# v0.8 deleted features/brew/Brewfile.work along with the profile axis. On the
# one machine that ran that profile, those 15 packages are installed and would
# otherwise become undeclared the moment the repo is pulled — which is exactly
# what `chez mirror` offers to uninstall. Nothing here uninstalls anything; it
# moves the declaration from a tier the repo no longer has to the one place a
# machine is allowed to keep its own answer, ~/.config/chez/Brewfile.local.
#
# The key carries a second passenger. The distiller falls back to `.profile` for
# its corpus scope, so this script copies the value into `memoryScope` before
# deleting the line it came from — see carry_scope_forward.
#
# Every step runs before the key is dropped, and the drop is conditional on all
# of them: the key is the marker the resolver fail-closes on and the hook's own
# render gate, so removing it after a failed move would lift the guard and
# consume the retry in the same breath.
#
# Called by src/.chezmoiscripts/run_once_before_00b-retire-work-profile.sh.tmpl,
# which renders a body only on a config that still carries the key. Idempotent
# anyway: entries already present are skipped and a config with no profile line
# is left alone, so a re-run after a partial failure is safe.
#
# The package list is inline rather than a file in the tree on purpose. It is
# not a tier and must never be resolved as one — brew_active_files, the CI
# Brewfile sweep and `chez doctor` all glob for Brewfiles, and a fifteenth
# reader finding this one would undo the whole point. It leaves with this
# script once every machine has migrated.
#
# Usage: migrate-work-profile.sh PROFILE CHEZMOI_CONFIG_FILE

set -uo pipefail

PROFILE="${1:-}"
CONFIG="${2:-}"

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$_DIR/../.." && pwd)"

# shellcheck source=../../core/ui.sh
. "$ROOT/core/ui.sh"
ui_init_logging
# tiers.sh owns the overlay's path and its seeding, and refuses to load without
# core/paths.sh. A hard dependency here: writing the work packages to a path
# this script guessed at, while every reader looks somewhere else, would leave
# the machine believing it had migrated when it had not.
# shellcheck source=lib/tiers.sh
if ! . "$ROOT/features/brew/lib/tiers.sh"; then
    fail "cannot load features/brew/lib/tiers.sh — not migrating"
    exit 1
fi

# The old features/brew/Brewfile.work, verbatim minus its header.
WORK_TIER='# ─── Cloud / Kubernetes / IaC ─────────────────────────────────────────────────
tap "Azure/kubelogin"
tap "hashicorp/tap"
brew "azure-cli"                 # account/subscription CLI
brew "Azure/kubelogin/kubelogin" # AKS auth plugin for kubectl
brew "hashicorp/tap/terraform"  # official tap (BUSL build)
brew "helm"                     # chart install/template/lint from the terminal
brew "kubectx"                  # + kubens
brew "kubernetes-cli"           # kubectl
brew "minikube"                 # local single-node cluster
cask "gcloud-cli"               # GCP account/project CLI

# ─── Work apps ────────────────────────────────────────────────────────────────
# microsoft-office is the full M365 suite; do not also list the standalone
# Word/Excel/Outlook/… casks — it `conflicts_with` them and `brew bundle` fails.
cask "intellij-idea"            # non-trivial Java/Kotlin work
cask "intune-company-portal"    # MDM enrolment; ships a .pkg, so it needs admin
cask "microsoft-office"
cask "microsoft-teams"
cask "slack"'

# _entry_keys — stdin → one `<kind> <name>` per declaration, ignoring comments,
# blank lines and trailing annotations. The comparison key for "is this already
# declared?", applied to BOTH the payload and the existing overlay so the two
# sides cannot disagree about what a line declares.
#
# Compared as whole strings rather than by grepping the file for each name: a
# package name is not a safe regex, and a false "already there" is the one
# mistake with teeth — it silently leaves a package undeclared. A false miss
# only ever costs a duplicate line, which `brew bundle` ignores.
_entry_keys() {
    sed -nE 's/^[[:space:]]*(brew|cask|tap|mas|vscode)[[:space:]]+"([^"]+)".*/\1 \2/p'
}

seed_overlay() {
    local overlay line key existing added=0 buf=""

    overlay="$(chez_local_brewfile)"
    if [ ! -f "$overlay" ] && ! brew_seed_local_brewfile "$ROOT"; then
        fail "could not create $overlay — not migrating the work packages"
        return 1
    fi
    # Checked before a single append, because `set -e` is deliberately off here:
    # an unchecked `>>` to a read-only overlay prints a permission error per
    # line and then falls through to "moved 15 work package(s)" and exit 0,
    # which is the one report that must never be wrong.
    if [ ! -w "$overlay" ]; then
        fail "$overlay is not writable — not migrating the work packages"
        return 1
    fi
    existing=$'\n'"$(_entry_keys <"$overlay" 2>/dev/null)"$'\n'

    while IFS= read -r line; do
        key="$(printf '%s\n' "$line" | _entry_keys)"
        # Headings and blank lines ride along with the entries under them, but
        # only if at least one entry below still needs writing — otherwise a
        # re-run would append the section furniture again and again.
        if [ -z "$key" ]; then
            buf="$buf$line"$'\n'
            continue
        fi
        case "$existing" in *$'\n'"$key"$'\n'*) continue ;; esac
        # One redirect for both writes, and its status checked: the open covers
        # a file that turned unwritable since the guard above, the printfs cover
        # a disk that filled underneath us. `added` must count lines that landed.
        if ! { printf '%s' "$buf" && printf '%s\n' "$line"; } >>"$overlay"; then
            fail "could not write to $overlay — the work packages are not all moved"
            return 1
        fi
        buf=""
        existing="$existing$key"$'\n'
        added=$((added + 1))
    done <<<"$WORK_TIER"

    if [ "$added" -eq 0 ]; then
        ok "the work packages are already declared in ${overlay/#$HOME/\~}"
        return 0
    fi
    ok "moved $added work package(s) into ${overlay/#$HOME/\~}"
    explain \
        "They are yours now: installed by every apply, never offered for" \
        "removal. Delete a line to hand that package back."
    return 0
}

# _data_key_line KEY — the line number of `KEY = …` inside the config's [data]
# table, or nothing. Scoped to the table on purpose: chezmoi's own config schema
# has an `awsSecretsManager.profile`, so a file-wide `grep '^ *profile *='`
# can match — and this script would then delete — a key that has nothing to do
# with the migration.
_data_key_line() {
    awk -v key="$1" '
        /^[[:space:]]*\[/ { in_data = ($0 ~ /^[[:space:]]*\[data\][[:space:]]*$/); next }
        in_data && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { print NR; exit }
    ' "$CONFIG"
}

# _config_rewrite TMP — move TMP over the config, keeping the config's mode.
#
# chezmoi creates that file 0600 and it holds corpusRemote, the signing key and
# an email. A plain `>` gives the temp file 0644 under the default umask, so
# without this the migration is the step that makes them world-readable.
#
# The probe validates the VALUE rather than an exit status, matching
# core/modules.sh's _modules_mv and statusline.sh's mtime read: BSD's `-f` is
# GNU's `--file-system`, which succeeds against a format string it does not
# understand, so a plain `a || b` never reaches the second spelling on Linux.
# This script only ever runs on macOS, but the suite that proves it runs on both.
_config_rewrite() {
    local tmp="$1" mode
    mode="$(stat -f '%Lp' "$CONFIG" 2>/dev/null || true)"
    case "$mode" in '' | *[!0-7]*) mode="$(stat -c '%a' "$CONFIG" 2>/dev/null || true)" ;; esac
    case "$mode" in '' | *[!0-7]*) mode="" ;; esac
    if [ -n "$mode" ]; then
        chmod "$mode" "$tmp" 2>/dev/null || true
    fi
    mv "$tmp" "$CONFIG"
}

# carry_scope_forward — copy the profile into `memoryScope` before the key that
# holds it is deleted.
#
# The distiller keys its corpus identity on `memoryScope` and falls back to
# `.profile` when that key is absent. Only `chezmoi init` ever writes
# memoryScope, and `chez up` never inits — so on the upgrade path this script is
# the last moment the old value exists anywhere at all.
#
# Deleting the profile without this does not fail; it disarms. Every leak
# boundary is written `[ -n "$mine" ] && …`, so an empty scope turns all of them
# into unconditional passes at once, and a corpus created afterwards is stamped
# `""` permanently — corpus.json is written once and never rewritten. Silent,
# and the exact outcome features/distill/lib/config.sh exists to prevent.
carry_scope_forward() {
    local n line value prefix indent tmp
    [ -n "$PROFILE" ] || return 0
    [ -n "$CONFIG" ] && [ -f "$CONFIG" ] || return 0
    # No profile line means nothing to carry and nothing to drop — the two are
    # the same edit seen from either end.
    n="$(_data_key_line profile)"
    [ -n "$n" ] || return 0
    if [ ! -w "$CONFIG" ]; then
        warn "${CONFIG/#$HOME/\~} is not writable — the profile key stays"
        explain "Make it writable and re-run, or remove the \`profile = …\` line by hand."
        return 1
    fi

    tmp="$CONFIG.carry-scope.tmp"
    local m
    m="$(_data_key_line memoryScope)"
    if [ -n "$m" ]; then
        line="$(awk -v n="$m" 'NR == n { print; exit }' "$CONFIG")"
        value="$(printf '%s' "${line#*=}" | tr -d '[:space:]"')"
        # A scope that is already answered wins. An EMPTY one is not an answer:
        # distill_scope skips empty strings, so leaving it would be the same
        # silent disarm as writing nothing at all.
        [ -n "$value" ] && return 0
        prefix="${line%%=*}"
        if awk -v n="$m" -v repl="$prefix= \"$PROFILE\"" \
            'NR == n { print repl; next } { print }' "$CONFIG" >"$tmp" &&
            _config_rewrite "$tmp"; then
            ok "kept this Mac's memory scope as \"$PROFILE\""
            return 0
        fi
    else
        line="$(awk -v n="$n" 'NR == n { print; exit }' "$CONFIG")"
        indent="${line%%[![:space:]]*}"
        if awk -v n="$n" -v repl="${indent}memoryScope = \"$PROFILE\"" \
            'NR == n { print; print repl; next } { print }' "$CONFIG" >"$tmp" &&
            _config_rewrite "$tmp"; then
            ok "kept this Mac's memory scope as \"$PROFILE\""
            return 0
        fi
    fi
    rm -f "$tmp"
    fail "could not write the memory scope into ${CONFIG/#$HOME/\~}"
    return 1
}

# drop_profile_key — remove `profile = "…"` from the generated chezmoi config.
#
# Line surgery for the same reason core/modules.sh does it: `chezmoi init` would
# re-derive every other answer, and this changes exactly one key. Once the key
# is gone the resolver in features/brew/lib/tiers.sh stops refusing, which is
# what makes this the last step rather than the first.
drop_profile_key() {
    local tmp n
    [ -n "$CONFIG" ] && [ -f "$CONFIG" ] || {
        warn "no chezmoi config at ${CONFIG:-<unset>} — leaving the profile key alone"
        return 0
    }
    n="$(_data_key_line profile)"
    [ -n "$n" ] || return 0
    if [ ! -w "$CONFIG" ]; then
        warn "${CONFIG/#$HOME/\~} is not writable — the profile key stays"
        explain "Remove the \`profile = …\` line by hand, or run \`chez setup\`."
        return 1
    fi
    tmp="$CONFIG.retire-profile.tmp"
    if awk -v n="$n" 'NR != n' "$CONFIG" >"$tmp" && _config_rewrite "$tmp"; then
        ok "removed the retired profile key from ${CONFIG/#$HOME/\~}"
        return 0
    fi
    rm -f "$tmp"
    fail "could not rewrite ${CONFIG/#$HOME/\~}"
    return 1
}

echo
printf '%s%s%s  %sRetiring the profile setting%s\n' "$CYAN" "$NODE" "$RESET" "$BOLD" "$RESET"
explain "A one-time change. Nothing is uninstalled and nothing is removed."

status=0
if [ "$PROFILE" = "work" ]; then
    seed_overlay || status=1
else
    ok "nothing to move — this Mac was set up as \"${PROFILE:-none}\""
fi
carry_scope_forward || status=1

# Dropping the key is the LAST step and it is conditional on every step above,
# because the key is also the marker. features/brew/lib/tiers.sh refuses to
# resolve a tier set while it is present, and the hook that calls this renders
# down to a bare `exit 0` once it is gone — so removing it after a failed move
# would both lift the guard and consume the only retry, permanently, leaving
# fifteen installed packages declared by nothing.
if [ "$status" -ne 0 ]; then
    echo
    fail "not migrated — the profile key stays, so nothing can be offered for removal"
    explain \
        "Nothing was uninstalled and nothing was lost. Fix the error above" \
        "and run \`chez up\` again; this step will retry from the start."
    exit 1
fi

drop_profile_key || exit 1
exit 0
