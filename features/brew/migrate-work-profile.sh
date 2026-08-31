#!/usr/bin/env bash
# migrate-work-profile.sh — one-time: retire the `profile` key from this Mac's
# chezmoi config, keeping every package the old `work` tier used to declare.
#
# v1.0 deleted features/brew/Brewfile.work along with the profile axis. On the
# one machine that ran that profile, those 15 packages are installed and would
# otherwise become undeclared the moment the repo is pulled — which is exactly
# what `chez mirror` offers to uninstall. Nothing here uninstalls anything; it
# moves the declaration from a tier the repo no longer has to the one place a
# machine is allowed to keep its own answer, ~/.config/chez/Brewfile.local.
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
        printf '%s' "$buf" >>"$overlay"
        buf=""
        printf '%s\n' "$line" >>"$overlay"
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

# drop_profile_key — remove `profile = "…"` from the generated chezmoi config.
#
# Line surgery for the same reason core/modules.sh does it: `chezmoi init` would
# re-derive every other answer, and this changes exactly one key. Once the key
# is gone the resolver in features/brew/lib/tiers.sh stops refusing, which is
# what makes this the last step rather than the first.
drop_profile_key() {
    local tmp
    [ -n "$CONFIG" ] && [ -f "$CONFIG" ] || {
        warn "no chezmoi config at ${CONFIG:-<unset>} — leaving the profile key alone"
        return 0
    }
    grep -qE '^[[:space:]]*profile[[:space:]]*=' "$CONFIG" || return 0
    if [ ! -w "$CONFIG" ]; then
        warn "${CONFIG/#$HOME/\~} is not writable — the profile key stays"
        explain "Remove the \`profile = …\` line by hand, or run \`chez setup\`."
        return 1
    fi
    tmp="$CONFIG.retire-profile.tmp"
    if grep -vE '^[[:space:]]*profile[[:space:]]*=' "$CONFIG" >"$tmp" && mv "$tmp" "$CONFIG"; then
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
drop_profile_key || status=1
exit "$status"
