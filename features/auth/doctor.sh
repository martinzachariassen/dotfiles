#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_auth() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# Informational by design — being signed out of a cloud CLI is a choice, not a
# fault, so nothing here fails.

doctor_auth() {
    section "Cloud auth (informational)"
    if command -v gh >/dev/null 2>&1; then
        if gh auth status >/dev/null 2>&1; then
            pass "gh authenticated"
        else note "gh not authenticated — run when needed: gh auth login"; fi
    fi
    if command -v az >/dev/null 2>&1; then
        if az account show >/dev/null 2>&1; then
            pass "az authenticated"
        else note "az not authenticated — run when needed: az login"; fi
        if command -v kubelogin >/dev/null 2>&1 && kubelogin --version 2>/dev/null | grep -qi 'git hash:'; then
            pass "Azure kubelogin installed"
        else
            warn "Azure kubelogin missing — run: az aks install-cli"
        fi
    fi
    if command -v gcloud >/dev/null 2>&1; then
        if gcloud auth list 2>/dev/null | grep -q '\*'; then
            pass "gcloud authenticated"
            if gcloud components list --filter='id=gke-gcloud-auth-plugin' --format='value(state.name)' 2>/dev/null | grep -q Installed; then
                pass "gke-gcloud-auth-plugin installed"
            else
                warn "gke-gcloud-auth-plugin missing — run: gcloud components install gke-gcloud-auth-plugin"
            fi
        else
            note "gcloud not authenticated — run when needed: gcloud auth login"
        fi
    fi
    if command -v op >/dev/null 2>&1; then
        # </dev/null avoids an interactive prompt; config.json absent means op was
        # never configured (desktop-only SSH setups), so there's nothing to check.
        if [ -f "$HOME/.config/op/config.json" ] || [ -f "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/Library/Application Support/1Password/Data/op/config.json" ]; then
            if op account list </dev/null >/dev/null 2>&1 && op vault list </dev/null >/dev/null 2>&1; then
                pass "1Password CLI signed in"
            else
                note "1Password CLI not signed in — run if you use op directly: eval \$(op signin)"
            fi
        else
            pass "1Password CLI not configured (desktop SSH integration is sufficient for this setup)"
        fi
    fi
}
