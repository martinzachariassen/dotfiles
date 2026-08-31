#!/usr/bin/env bash
# bootstrap-auth.sh — idempotent post-install account/auth walkthrough; each
# step probes existing state and skips if already signed in.
# Env: SKIP_GH SKIP_AZ SKIP_AKS SKIP_GCLOUD SKIP_GKE SKIP_OP SKIP_SIGNTEST=1 skips
#      that step; YES=1 skips pause prompts.

set -uo pipefail

ASSUME_YES="${YES:-0}"

# log.sh is a committed sibling; fail loudly if a checkout is missing it.
_UI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$_UI_DIR/../../core/ui.sh" ]; then
    printf 'bootstrap-auth: missing %s\n' "$_UI_DIR/../../core/ui.sh" >&2
    exit 1
fi
# shellcheck source=../../core/ui.sh
. "$_UI_DIR/../../core/ui.sh"
ui_init_logging

# The signing smoke test belongs to the sign feature; auth borrows it rather
# than keeping a second copy of the 1Password agent probe.
# shellcheck source=../sign/lib.sh
if [ -r "$_UI_DIR/../sign/lib.sh" ]; then
    . "$_UI_DIR/../sign/lib.sh"
fi
# shellcheck source=../../core/chezmoi-data.sh
if [ -r "$_UI_DIR/../../core/chezmoi-data.sh" ]; then
    . "$_UI_DIR/../../core/chezmoi-data.sh"
fi

# has_module NAME — true when NAME is in the selected .modules list.
has_module() {
    command -v chezmoi >/dev/null 2>&1 || return 1
    cm_has_module "$(cm_data_json)" "$1"
}

box_line() {
    local text="$1" pre="${2:-}" post="${3:-}" pad
    pad=$((58 - ${#text}))
    [ "$pad" -lt 0 ] && pad=1
    printf "%s  %s%s%s%*s%s\n" "$(line_prefix)" "$pre" "$text" "$post" "$pad" "" "$(line_prefix)"
}

step() {
    echo
    printf "%s  %s%s%s\n" "$(node_prefix)" "$BOLD" "$1" "$RESET"
    printf "%s  %s%s%s\n" "$(line_prefix)" "$DIM" "$2" "$RESET"
    echo
}

pause_for_enter() {
    local prompt="$1"
    [ "$ASSUME_YES" = "1" ] && return 0
    [ -t 0 ] || return 0
    printf "%s  %s" "$(line_prefix)" "$prompt"
    IFS= read -r _
}

banner() {
    echo
    printf "%s\n" "${CYAN}${BOX_TOP}${RESET}"
    box_line "Bootstrap Auth" "$BOLD" "$RESET"
    printf "%s\n" "${CYAN}${BOX_BOTTOM}${RESET}"
    echo
    say "This finishes account sign-in and git signing after the machine setup."
    say "Already-authenticated tools are skipped."
    hr
    say "1Password   checks the desktop SSH agent"
    say "gh          opens GitHub OAuth if needed"
    say "az          signs in when Azure CLI is installed"
    say "gcloud      signs in when Google Cloud CLI is installed"
    hr
    pause_for_enter "Press Enter to begin account setup "
}

banner

if [ "${SKIP_OP:-0}" != "1" ]; then
    step "1Password" "Open the app, sign in, enable the SSH agent: Settings -> Developer."
    if [ ! -d /Applications/1Password.app ]; then
        fail "1Password.app missing - run install.sh or brew bundle first"
    elif pgrep -xq 1Password; then
        ok "1Password is running"
    else
        info "launching 1Password GUI"
        open -a 1Password
        warn "Sign in, then enable Settings -> Developer -> SSH agent."
        pause_for_enter "Press Enter after 1Password is signed in and the SSH agent is enabled "
    fi
    OP_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    if [ -S "$OP_SOCK" ]; then
        ok "1Password SSH agent socket present"
    else
        warn "SSH agent socket not found at $OP_SOCK - check Settings -> Developer -> SSH agent"
    fi
fi

if [ "${SKIP_GH:-0}" != "1" ]; then
    step "GitHub CLI" "Authenticate gh so you can push, create PRs, and use \`gh pr checkout\`."
    if ! command -v gh >/dev/null 2>&1; then
        fail "gh not installed - run install.sh"
    elif gh auth status >/dev/null 2>&1; then
        ok "gh already authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')"
    else
        info "running gh auth login (use SSH protocol for git operations)"
        gh auth login -p ssh -h github.com -w || warn "gh auth login was cancelled or failed"
    fi
fi

if [ "${SKIP_AZ:-0}" != "1" ] && has_module cloudAuth; then
    step "Azure CLI" "Sign in to Azure for AKS, Azure DevOps, etc."
    if ! command -v az >/dev/null 2>&1; then
        warn "az not installed - skipping. Use the work profile if this Mac needs Azure."
    elif az account show >/dev/null 2>&1; then
        ok "az already authenticated as $(az account show --query user.name -o tsv 2>/dev/null || echo '?')"
    else
        info "running az login"
        az login || warn "az login was cancelled or failed"
    fi

    # az aks install-cli, not brew's kubelogin (int128's generic OIDC plugin) —
    # that's not the AKS binary Microsoft documents.
    if [ "${SKIP_AKS:-0}" != "1" ] && command -v az >/dev/null 2>&1; then
        step "AKS kubelogin" "Required for kubectl against AKS clusters using Microsoft Entra ID."
        if command -v kubelogin >/dev/null 2>&1 && kubelogin --version 2>/dev/null | grep -qi 'git hash:'; then
            ok "Azure kubelogin already installed"
        else
            info "installing Azure kubelogin via az aks install-cli"
            az aks install-cli || warn "Azure kubelogin install failed"
        fi
    fi
fi

if [ "${SKIP_GCLOUD:-0}" != "1" ] && has_module cloudAuth; then
    step "Google Cloud CLI" "Sign in for GCP/GKE work."
    if ! command -v gcloud >/dev/null 2>&1; then
        warn "gcloud not installed - skipping. Use the work profile if this Mac needs GCP."
    elif gcloud auth list 2>/dev/null | grep -q '\*'; then
        ok "gcloud already authenticated as $(gcloud config get-value account 2>/dev/null || echo '?')"
    else
        info "running gcloud auth login"
        gcloud auth login || warn "gcloud auth login was cancelled or failed"
    fi
    # ADC is separate from the user-account login; many SDKs and Terraform want it.
    if command -v gcloud >/dev/null 2>&1; then
        if [ -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
            ok "ADC already configured"
        else
            info "configuring application-default credentials"
            gcloud auth application-default login || warn "ADC setup was cancelled or failed"
        fi
    fi

    # GKE plugin is a gcloud component, not a brew formula.
    if [ "${SKIP_GKE:-0}" != "1" ] && command -v gcloud >/dev/null 2>&1; then
        step "GKE auth plugin" "Required for kubectl 1.26+ to talk to GKE clusters."
        if gcloud components list --filter='id=gke-gcloud-auth-plugin' \
            --format='value(state.name)' 2>/dev/null | grep -q Installed; then
            ok "gke-gcloud-auth-plugin already installed"
        else
            info "installing gke-gcloud-auth-plugin"
            gcloud components install -q gke-gcloud-auth-plugin || warn "GKE plugin install failed"
        fi
    fi
fi

if [ "${SKIP_OP:-0}" != "1" ]; then
    step "1Password CLI" "The \`op\` CLI - used by chezmoi if you template secrets."
    if ! command -v op >/dev/null 2>&1; then
        warn "op not installed - skipping (in Brewfile)"
    else
        # </dev/null: op account/vault list prompt interactively with no accounts configured.
        if op account list </dev/null >/dev/null 2>&1 && op vault list </dev/null >/dev/null 2>&1; then
            ok "op CLI already signed in"
        else
            info "op CLI not signed in. For most flows you don't need this -"
            info "  1Password's SSH agent + git signing go through the desktop"
            info "  app, not via \`op\`. Only set up the CLI if you actually use"
            info "  it (chezmoi templates that pull secrets, op-injected envs)."
            warn "To set up: op account add, then eval \$(op signin)"
        fi
    fi
fi

if [ "${SKIP_SIGNTEST:-0}" != "1" ]; then
    step "Git signing config" "Signing (signingMode + signingKey) is owned by the setup wizard."
    gitkey="$(git config --global user.signingkey 2>/dev/null || true)"
    if [ -n "$gitkey" ]; then
        ok "git signing key already configured"
    else
        warn "no git signing key configured yet"
        info "Set it by re-running the wizard, then applying:"
        dim "    chezmoi init --prompt      # choose signingMode, paste the public key"
        dim "    chez apply"
    fi
fi

# The smoke test is specific to signingMode = 1password. Under `ssh-key` or
# `off` the git config it asserts is deliberately absent, so running it there
# reports a wall of failures for a correctly configured machine.
signing_mode=""
if command -v cm_data_json >/dev/null 2>&1; then
    signing_mode="$(cm_data_string "$(cm_data_json)" "signingMode")"
fi
if [ "${SKIP_SIGNTEST:-0}" != "1" ] && [ "$signing_mode" != "off" ] && [ "$signing_mode" != "ssh-key" ]; then
    step "Git signing smoke test" "Verifies op-ssh-sign + 1Password agent + your git config all line up."
    # git-signing.sh is sourced conditionally above; `set -u` would abort here.
    SSH_SIGN="${GIT_SIGNING_SSH_SIGN:-}"
    if [ -z "$SSH_SIGN" ]; then
        warn "features/sign/lib.sh not readable - skipping the smoke test"
    elif [ ! -x "$SSH_SIGN" ]; then
        fail "op-ssh-sign missing - install/launch 1Password and enable the SSH agent"
    elif [ -z "$(git config --global user.signingkey 2>/dev/null)" ]; then
        warn "no signing key in git config - re-run this script and paste the 1Password public key"
    elif [ "$(git config --global commit.gpgsign 2>/dev/null)" != "true" ]; then
        fail "git commit.gpgsign is not true - run \`chezmoi apply\`"
    elif [ "$(git config --global gpg.format 2>/dev/null)" != "ssh" ]; then
        fail "git gpg.format is not ssh - run \`chezmoi apply\`"
    elif [ "$(git config --global gpg.ssh.program 2>/dev/null)" != "$SSH_SIGN" ]; then
        fail "git gpg.ssh.program is not op-ssh-sign - run \`chezmoi apply\`"
    elif [ ! -f "$(git config --global --path gpg.ssh.allowedSignersFile 2>/dev/null)" ]; then
        fail "git allowed signers file missing - run \`chezmoi apply\`"
    else
        if git_signing_smoke_test; then
            ok "git -S commit succeeded - signing wired correctly"
        else
            fail "git -S commit failed - is 1Password unlocked? SSH agent enabled?"
            warn "Check: 1Password -> Settings -> Developer -> SSH agent"
        fi
    fi
fi

echo
printf "%s\n" "${CYAN}${BOX_TOP}${RESET}"
box_line "Auth bootstrap complete" "${GREEN}${BOLD}" "$RESET"
printf "%s\n" "${CYAN}${BOX_BOTTOM}${RESET}"
echo
say "${BOLD}Next${RESET}"
say "exec zsh       reload your shell"
say "chez doctor     run the full health check"
say "Restart macOS  finish any system defaults that need a reboot"
echo
dim "Re-run this script anytime; it skips steps already done."
