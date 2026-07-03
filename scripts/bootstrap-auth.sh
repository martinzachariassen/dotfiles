#!/usr/bin/env bash
# bootstrap-auth.sh - post-install authentication walkthrough.
#
# install.sh sets up the *machine*. This sets up the *accounts* - the
# manual-tail step list that used to live at the end of the README.
#
# Idempotent: every step probes existing state first and skips if you're
# already signed in.
#
# Usage:
#   bash ~/Developer/personal/dotfiles/scripts/bootstrap-auth.sh
#
# Environment variables:
#   SKIP_GH=1       skip gh auth login
#   SKIP_AZ=1       skip az login
#   SKIP_AKS=1      skip Azure kubelogin install
#   SKIP_GCLOUD=1   skip gcloud auth login
#   SKIP_GKE=1      skip gke-gcloud-auth-plugin install
#   SKIP_OP=1       skip 1Password GUI/CLI checks
#   SKIP_SIGNTEST=1 skip git signing config + smoke test
#   YES=1           run without pause prompts

set -uo pipefail

SOURCE_DIR="${DOTFILES_DIR:-$(chezmoi source-path 2>/dev/null || echo "$HOME/Developer/personal/dotfiles")}"
ASSUME_YES="${YES:-0}"

# Shared UI engine (colors, glyphs, and the rail-style log helpers:
# line_prefix/node_prefix/say/ok/info/warn/fail/dim/hr). ui.sh is a committed
# sibling of this script; a checkout without it is broken, so fail loudly rather
# than limp along with degraded output (chezup.sh does the same).
_UI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$_UI_DIR/lib/ui.sh" ]; then
    printf 'bootstrap-auth: missing %s\n' "$_UI_DIR/lib/ui.sh" >&2
    exit 1
fi
# shellcheck source=lib/ui.sh
. "$_UI_DIR/lib/ui.sh"
ui_init_logging

# bootstrap-specific framing on top of the shared log helpers.
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

# ─── 1. 1Password GUI / SSH agent ─────────────────────────────────────────────
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
    # Verify the SSH agent socket is exported via the standard 1Password path.
    OP_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    if [ -S "$OP_SOCK" ]; then
        ok "1Password SSH agent socket present"
    else
        warn "SSH agent socket not found at $OP_SOCK - check Settings -> Developer -> SSH agent"
    fi
fi

# ─── 2. GitHub CLI ────────────────────────────────────────────────────────────
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

# ─── 3. Azure CLI + AKS kubelogin ─────────────────────────────────────────────
if [ "${SKIP_AZ:-0}" != "1" ]; then
    step "Azure CLI" "Sign in to Azure for AKS, Azure DevOps, etc."
    if ! command -v az >/dev/null 2>&1; then
        warn "az not installed - skipping. Use the work profile if this Mac needs Azure."
    elif az account show >/dev/null 2>&1; then
        ok "az already authenticated as $(az account show --query user.name -o tsv 2>/dev/null || echo '?')"
    else
        info "running az login"
        az login || warn "az login was cancelled or failed"
    fi

    # Azure kubelogin (Microsoft's AKS credential plugin). Homebrew core also
    # has a `kubelogin` formula, but that is int128's generic OIDC plugin, not
    # the AKS-focused binary Microsoft documents for `az aks`.
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

# ─── 4. Google Cloud CLI + GKE plugin ─────────────────────────────────────────
if [ "${SKIP_GCLOUD:-0}" != "1" ]; then
    step "Google Cloud CLI" "Sign in for GCP/GKE work."
    if ! command -v gcloud >/dev/null 2>&1; then
        warn "gcloud not installed - skipping. Use the work profile if this Mac needs GCP."
    elif gcloud auth list 2>/dev/null | grep -q '\*'; then
        ok "gcloud already authenticated as $(gcloud config get-value account 2>/dev/null || echo '?')"
    else
        info "running gcloud auth login"
        gcloud auth login || warn "gcloud auth login was cancelled or failed"
    fi
    # Application-default credentials - separate from the user-account login.
    # Many SDKs and Terraform providers want this.
    if command -v gcloud >/dev/null 2>&1; then
        if [ -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
            ok "ADC already configured"
        else
            info "configuring application-default credentials"
            gcloud auth application-default login || warn "ADC setup was cancelled or failed"
        fi
    fi

    # GKE plugin (gcloud component, NOT a brew formula).
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

# ─── 5. 1Password CLI ─────────────────────────────────────────────────────────
if [ "${SKIP_OP:-0}" != "1" ]; then
    step "1Password CLI" "The \`op\` CLI - used by chezmoi if you template secrets."
    if ! command -v op >/dev/null 2>&1; then
        warn "op not installed - skipping (in Brewfile)"
    else
        # `op account list` and `op vault list` are interactive when no
        # accounts are configured - they print "No accounts configured..." and
        # prompt "Do you want to add an account manually now? [Y/n]". We close
        # stdin with </dev/null so this script never gets ambushed by that.
        # If you DO want to set up op CLI, the warn-block below gives the
        # exact commands to run manually.
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

# ─── 6. Git signing config ────────────────────────────────────────────────────
if [ "${SKIP_SIGNTEST:-0}" != "1" ]; then
    step "Git signing config" "Signing (signingMode + signingKey) is owned by the setup wizard."
    gitkey="$(git config --global user.signingkey 2>/dev/null || true)"
    if [ -n "$gitkey" ]; then
        ok "git signing key already configured"
    else
        warn "no git signing key configured yet"
        info "Set it by re-running the wizard, then applying:"
        dim "    chezmoi init --prompt      # choose signingMode, paste the public key"
        dim "    chez"
    fi
fi

# ─── 7. Git signing smoke test ────────────────────────────────────────────────
if [ "${SKIP_SIGNTEST:-0}" != "1" ]; then
    step "Git signing smoke test" "Verifies op-ssh-sign + 1Password agent + your git config all line up."
    SSH_SIGN=/Applications/1Password.app/Contents/MacOS/op-ssh-sign
    if [ ! -x "$SSH_SIGN" ]; then
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
        tmpdir=$(mktemp -d)
        if (
            cd "$tmpdir" &&
                git init -q -b main &&
                git -c user.email=bootstrap@local -c user.name=Bootstrap commit \
                    --allow-empty --quiet -S -m bootstrap-test 2>&1
        ) >/dev/null 2>&1; then
            ok "git -S commit succeeded - signing wired correctly"
        else
            fail "git -S commit failed - is 1Password unlocked? SSH agent enabled?"
            warn "Check: 1Password -> Settings -> Developer -> SSH agent"
        fi
        rm -rf "$tmpdir"
    fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo
printf "%s\n" "${CYAN}${BOX_TOP}${RESET}"
box_line "Auth bootstrap complete" "${GREEN}${BOLD}" "$RESET"
printf "%s\n" "${CYAN}${BOX_BOTTOM}${RESET}"
echo
say "${BOLD}Next${RESET}"
say "exec zsh       reload your shell"
say "chezdoctor     run the full health check"
say "Restart macOS  finish any system defaults that need a reboot"
echo
dim "Re-run this script anytime; it skips steps already done."
