#!/usr/bin/env bash
# bootstrap-auth.sh — post-install authentication walkthrough.
#
# install.sh sets up the *machine*. This sets up the *accounts* — the
# manual-tail step list that used to live at the end of the README.
#
# Idempotent: every step probes existing state first and skips if you're
# already signed in.
#
# Usage:
#   bash ~/Developer/personal/dotfiles/scripts/bootstrap-auth.sh
#
# Environment variables:
#   SKIP_GH=1       — skip gh auth login
#   SKIP_AZ=1       — skip az login
#   SKIP_AKS=1      — skip Azure kubelogin install
#   SKIP_GCLOUD=1   — skip gcloud auth login
#   SKIP_GKE=1      — skip gke-gcloud-auth-plugin install
#   SKIP_OP=1       — skip 1Password CLI signin
#   SKIP_SIGNTEST=1 — skip the git signing smoke test

set -uo pipefail

if [ -t 1 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'
    GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RED=$'\033[31m'
    RESET=$'\033[0m'
else
    BOLD=""; DIM=""; GREEN=""; YELLOW=""; BLUE=""; RED=""; RESET=""
fi

step() { echo; echo "${BOLD}${BLUE}══ $1 ══${RESET}"; echo "${DIM}$2${RESET}"; echo; }
ok()   { echo "  ${GREEN}✓${RESET}  $1"; }
info() { echo "  ${BLUE}ℹ${RESET}  $1"; }
warn() { echo "  ${YELLOW}!${RESET}  $1"; }
fail() { echo "  ${RED}✗${RESET}  $1"; }

cat <<EOF

${BOLD}Bootstrap auth${RESET}
${DIM}Walks through the manual sign-in steps after install.sh.${RESET}

${BOLD}You'll be prompted by the following CLIs:${RESET}
  • 1Password   — open the GUI app and sign in (we just check the agent)
  • gh          — opens a browser for GitHub OAuth
  • az          — opens a browser for Microsoft account and checks AKS kubelogin
  • gcloud      — opens a browser for Google account and checks the GKE plugin

Each is skipped if you're already signed in. Missing CLIs are reported and skipped. Press ${BOLD}Enter${RESET} to begin.
EOF
[ -t 0 ] && read -r _

# ─── 1. 1Password GUI / SSH agent ─────────────────────────────────────────────
if [ "${SKIP_OP:-0}" != "1" ]; then
    step "1Password" "Open the app, sign in, enable the SSH agent (Settings → Developer)."
    if [ ! -d /Applications/1Password.app ]; then
        fail "1Password.app missing — install via brew bundle"
    elif pgrep -xq 1Password; then
        ok "1Password is running"
    else
        info "launching 1Password GUI"
        open -a 1Password
        warn "Sign in, then enable the SSH agent. Press Enter when done."
        [ -t 0 ] && read -r _
    fi
    # Verify the SSH agent socket is exported via the standard 1Password path.
    OP_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    if [ -S "$OP_SOCK" ]; then
        ok "1Password SSH agent socket present"
    else
        warn "SSH agent socket not found at $OP_SOCK — check Settings → Developer → SSH agent"
    fi
fi

# ─── 2. GitHub CLI ────────────────────────────────────────────────────────────
if [ "${SKIP_GH:-0}" != "1" ]; then
    step "GitHub CLI" "Authenticate gh so you can push, create PRs, and use \`gh pr checkout\`."
    if ! command -v gh >/dev/null 2>&1; then
        fail "gh not installed — run install.sh"
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
        warn "az not installed — skipping (run install.sh or brew bundle)"
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
        warn "gcloud not installed — skipping (run install.sh or brew bundle)"
    elif gcloud auth list 2>/dev/null | grep -q '\*'; then
        ok "gcloud already authenticated as $(gcloud config get-value account 2>/dev/null || echo '?')"
    else
        info "running gcloud auth login"
        gcloud auth login || warn "gcloud auth login was cancelled or failed"
    fi
    # Application-default credentials — separate from the user-account login.
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
        step "GKE auth plugin" "Required for kubectl ≥ 1.26 to talk to GKE clusters."
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
    step "1Password CLI" "The \`op\` CLI — used by chezmoi if you template secrets."
    if ! command -v op >/dev/null 2>&1; then
        warn "op not installed — skipping (in Brewfile)"
    else
        # `op account list` and `op vault list` are interactive when no
        # accounts are configured — they print "No accounts configured…" and
        # prompt "Do you want to add an account manually now? [Y/n]". We close
        # stdin with </dev/null so this script never gets ambushed by that.
        # If you DO want to set up op CLI, the warn-block below gives the
        # exact commands to run manually.
        if op account list </dev/null >/dev/null 2>&1 && op vault list </dev/null >/dev/null 2>&1; then
            ok "op CLI already signed in"
        else
            info "op CLI not signed in. For most flows you don't need this —"
            info "  1Password's SSH agent + git signing go through the desktop"
            info "  app, not via \`op\`. Only set up the CLI if you actually use"
            info "  it (chezmoi templates that pull secrets, op-injected envs)."
            warn "To set up:  op account add   →   eval \$(op signin)"
        fi
    fi
fi

# ─── 6. Git signing smoke test ────────────────────────────────────────────────
if [ "${SKIP_SIGNTEST:-0}" != "1" ]; then
    step "Git signing smoke test" "Verifies op-ssh-sign + 1Password agent + your git config all line up."
    SSH_SIGN=/Applications/1Password.app/Contents/MacOS/op-ssh-sign
    if [ ! -x "$SSH_SIGN" ]; then
        fail "op-ssh-sign missing — install/launch 1Password and enable the SSH agent"
    elif [ -z "$(git config --global user.signingkey 2>/dev/null)" ]; then
        warn "no signing key in git config — run \`chezmoi init\` to re-prompt"
    else
        tmpdir=$(mktemp -d)
        if (
            cd "$tmpdir" &&
            git init -q -b main &&
            git -c user.email=bootstrap@local -c user.name=Bootstrap commit \
                --allow-empty --quiet -S -m bootstrap-test 2>&1
        ) >/dev/null 2>&1; then
            ok "git -S commit succeeded → signing wired correctly"
        else
            fail "git -S commit failed — is 1Password unlocked? SSH agent enabled?"
            warn "Check: 1Password → Settings → Developer → SSH agent"
        fi
        rm -rf "$tmpdir"
    fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
cat <<EOF

${BOLD}${GREEN}Auth bootstrap complete.${RESET}

${BOLD}Suggested next:${RESET}
  • ${BOLD}exec zsh${RESET}                      reload your shell
  • ${BOLD}chezdoctor${RESET}                    run the full health check
  • ${BOLD}Restart your Mac${RESET}              some macOS defaults need a reboot to take effect

${DIM}Re-run this script anytime — it skips steps already done.${RESET}
EOF
