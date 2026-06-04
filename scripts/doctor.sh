#!/usr/bin/env bash
# doctor.sh — health check for the dotfiles install on this machine.
#
# Run anytime (idempotent, read-only):
#   bash ~/Developer/personal/dotfiles/scripts/doctor.sh
#   chezdoctor                                 # zsh alias
#
# Output convention:
#   ✓ green = passing
#   ! yellow = warning (not broken, but worth knowing)
#   ✗ red   = failing (needs your attention)
#
# Exit codes:
#   0  — everything passes (warnings are still 0)
#   1  — at least one fail
#
# Why a script and not just `chezmoi doctor`:
#   chezmoi's built-in doctor checks chezmoi's own state. This script checks the
#   *whole stack* this repo expects — XDG layout, claude config, op
#   signing, brew bundle drift, auth state — anything that can quietly break and
#   bite you a week later.

set -uo pipefail

# ─── Color ────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'
    GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RED=$'\033[31m'
    RESET=$'\033[0m'
else
    BOLD=""; DIM=""; GREEN=""; YELLOW=""; BLUE=""; RED=""; RESET=""
fi

PASS=0
ACTION=0
INFOCOUNT=0
FAIL=0

pass() { echo "  ${GREEN}✓${RESET}  $1"; PASS=$((PASS + 1)); }
warn() { echo "  ${YELLOW}!${RESET}  $1"; ACTION=$((ACTION + 1)); }
note() { echo "  ${BLUE}•${RESET}  $1"; INFOCOUNT=$((INFOCOUNT + 1)); }
fail() { echo "  ${RED}✗${RESET}  $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "${BOLD}${BLUE}── $1 ──${RESET}"; }

SOURCE_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"

# Shared helpers (semver_extract / semver_lt). Loaded from next to this script
# so the version check below works even when DOTFILES_DIR is overridden.
_DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/semver.sh
if [ -r "$_DOCTOR_DIR/lib/semver.sh" ]; then
    . "$_DOCTOR_DIR/lib/semver.sh"
fi

# ─── 1. Source repo present and up to date ────────────────────────────────────
section "Source repo"
if [ -d "$SOURCE_DIR/.git" ]; then
    pass "repo at $SOURCE_DIR"
    if (cd "$SOURCE_DIR" && git fetch -q origin 2>/dev/null); then
        local_head=$(cd "$SOURCE_DIR" && git rev-parse @ 2>/dev/null || echo "")
        remote_head=$(cd "$SOURCE_DIR" && git rev-parse '@{u}' 2>/dev/null || echo "")
        if [ -n "$local_head" ] && [ "$local_head" = "$remote_head" ]; then
            pass "repo in sync with origin"
        elif [ -n "$local_head" ] && [ -n "$remote_head" ]; then
            warn "repo behind/ahead of origin — run \`chezup\` to sync"
        fi
    fi
    # Uncommitted changes in repo
    if (cd "$SOURCE_DIR" && [ -n "$(git status --porcelain 2>/dev/null)" ]); then
        warn "repo has uncommitted changes — run \`cd $SOURCE_DIR && git status\`"
    else
        pass "repo working tree clean"
    fi
else
    fail "repo missing at $SOURCE_DIR — re-run install.sh"
fi

# ─── 2. chezmoi config + minVersion ───────────────────────────────────────────
section "chezmoi"
if command -v chezmoi >/dev/null 2>&1; then
    pass "chezmoi installed: $(chezmoi --version | head -1)"
    # Compare installed version against the repo's pinned minimum
    # (.chezmoiversion). chezmoi refuses to read the source if it's too old, but
    # being far ahead is worth knowing too since template helpers shift between
    # releases.
    if command -v semver_lt >/dev/null 2>&1 && [ -r "$SOURCE_DIR/.chezmoiversion" ]; then
        min_ver="$(semver_extract "$(cat "$SOURCE_DIR/.chezmoiversion")")"
        cur_ver="$(semver_extract "$(chezmoi --version 2>/dev/null)")"
        if [ -n "$min_ver" ] && [ -n "$cur_ver" ]; then
            if semver_lt "$cur_ver" "$min_ver"; then
                fail "chezmoi $cur_ver is older than the repo minimum $min_ver — run: brew upgrade chezmoi"
            else
                pass "chezmoi $cur_ver meets repo minimum $min_ver"
            fi
        fi
    fi
    if chezmoi doctor 2>&1 | grep -q '^error'; then
        fail "chezmoi doctor reports errors — run: chezmoi doctor"
    else
        pass "chezmoi doctor clean"
    fi
    # Drift between source and $HOME. Exclude scripts because run_* entries can
    # remain pending after a successful apply by design.
    drift=$(chezmoi status --exclude scripts 2>/dev/null | wc -l | tr -d ' ')
    if [ "$drift" = "0" ]; then
        pass "no drift between source and \$HOME"
    else
        warn "$drift file(s) drifted — run \`chez\` to apply or \`chezmoi diff\` to inspect"
    fi
else
    fail "chezmoi not installed — re-run install.sh"
fi

# ─── 3. XDG layout: legacy files must NOT exist ───────────────────────────────
section "XDG layout"
for legacy in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.gitconfig" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile"; do
    if [ -f "$legacy" ]; then
        fail "legacy $legacy present — would shadow XDG-managed config. Run \`chez\` to remove."
    else
        pass "no legacy $(basename "$legacy")"
    fi
done
# Required ZDOTDIR file
if [ -f "$HOME/.config/zsh/.zshrc" ]; then
    pass "~/.config/zsh/.zshrc present"
else
    fail "~/.config/zsh/.zshrc missing — run: chezmoi apply"
fi
# .zshenv must stay in $HOME (zsh reads it before ZDOTDIR is set)
if [ -f "$HOME/.zshenv" ]; then
    pass "~/.zshenv present (must stay in \$HOME)"
else
    fail "~/.zshenv missing — run: chezmoi apply"
fi

# ─── 4. Claude config ─────────────────────────────────────────────────────────
section "Claude config"
ccdir=$(zsh -c 'source "$HOME/.zshenv" >/dev/null 2>&1; printf %s "${CLAUDE_CONFIG_DIR:-}"')
if [ "$ccdir" = "$HOME/.config/claude" ]; then
    pass "CLAUDE_CONFIG_DIR points at ~/.config/claude"
else
    fail "CLAUDE_CONFIG_DIR is '${ccdir:-unset}' (expected ~/.config/claude) — run: chezmoi apply"
fi
if [ -f "$HOME/.config/claude/CLAUDE.shared.md" ]; then
    pass "~/.config/claude/CLAUDE.shared.md present"
else
    fail "~/.config/claude/CLAUDE.shared.md missing — run: chezmoi apply"
fi
if [ -f "$HOME/.config/claude/CLAUDE.md" ]; then
    pass "~/.config/claude/CLAUDE.md present (active profile)"
else
    fail "~/.config/claude/CLAUDE.md missing — run: chezmoi apply"
fi

# ─── 5. Git signing via 1Password ─────────────────────────────────────────────
section "Git signing (1Password SSH agent)"
SSH_SIGN=/Applications/1Password.app/Contents/MacOS/op-ssh-sign
if [ -x "$SSH_SIGN" ]; then
    pass "op-ssh-sign present"
else
    fail "op-ssh-sign missing — install 1Password app and enable SSH agent in Settings → Developer"
fi
# The signing key configured in git
gitkey=$(git config --global user.signingkey 2>/dev/null || true)
if [ -n "$gitkey" ]; then
    pass "git signing key configured"
    if [ "$(git config --global commit.gpgsign 2>/dev/null || true)" = "true" ]; then
        pass "git commit signing enabled"
    else
        warn "git commit.gpgsign is not true — run \`chezmoi apply\`"
    fi
    if [ "$(git config --global gpg.format 2>/dev/null || true)" = "ssh" ]; then
        pass "git SSH signing format configured"
    else
        warn "git gpg.format is not ssh — run \`chezmoi apply\`"
    fi
    if [ "$(git config --global gpg.ssh.program 2>/dev/null || true)" = "$SSH_SIGN" ]; then
        pass "git 1Password SSH signer configured"
    else
        warn "git gpg.ssh.program is not op-ssh-sign — run \`chezmoi apply\`"
    fi
    allowed_signers="$(git config --global --path gpg.ssh.allowedSignersFile 2>/dev/null || true)"
    if [ -n "$allowed_signers" ] && [ -f "$allowed_signers" ]; then
        pass "git allowed signers file present"
    else
        warn "git allowed signers file missing — run \`chezmoi apply\`"
    fi
else
    warn "no git signing key set — run bootstrap-auth.sh after signing in to 1Password"
fi
# Smoke-test signing in a tmp repo (proves agent is reachable + key matches).
if [ -x "$SSH_SIGN" ] && [ -n "$gitkey" ]; then
    tmpdir=$(mktemp -d)
    if (
        cd "$tmpdir" &&
        git init -q -b main &&
        git -c user.email=doctor@local -c user.name=Doctor commit \
            --allow-empty --quiet -S -m doctor 2>&1
    ) >/dev/null 2>&1; then
        pass "git signing works (commit -S succeeded)"
    else
        warn "git -S commit failed — is 1Password unlocked + SSH agent enabled?"
    fi
    rm -rf "$tmpdir"
fi

# ─── 6. Brewfile sync ─────────────────────────────────────────────────────────
section "Homebrew packages"
if command -v brew >/dev/null 2>&1; then
    pass "brew installed"
    if [ -f "$SOURCE_DIR/Brewfile" ]; then
        if brew bundle check --file="$SOURCE_DIR/Brewfile" >/dev/null 2>&1; then
            pass "common Brewfile satisfied"
        else
            warn "common Brewfile out of sync — run: brew bundle install --file=$SOURCE_DIR/Brewfile"
        fi
    fi
    # Feature/profile-specific modules.
    data_json="$(chezmoi data --format=json 2>/dev/null || echo '{}')"
    if command -v jq >/dev/null 2>&1; then
        profile="$(printf '%s\n' "$data_json" | jq -r '.profile // empty')"
        feature_ai="$(printf '%s\n' "$data_json" | jq -r '.features.ai // false')"
        feature_macapps="$(printf '%s\n' "$data_json" | jq -r '.features.macApps // true')"
    else
        profile="$(printf '%s\n' "$data_json" | sed -n 's/.*"profile"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tail -1)"
        feature_ai="$(printf '%s\n' "$data_json" | sed -n 's/.*"ai"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | tail -1)"
        feature_macapps="$(printf '%s\n' "$data_json" | sed -n 's/.*"macApps"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | tail -1)"
        feature_ai="${feature_ai:-false}"
        feature_macapps="${feature_macapps:-true}"
    fi
    if [ "$feature_ai" = "true" ]; then
        if brew bundle check --file="$SOURCE_DIR/brewfiles/Brewfile.ai" >/dev/null 2>&1; then
            pass "ai Brewfile satisfied"
        else
            warn "Brewfile.ai out of sync — run: brew bundle install --file=$SOURCE_DIR/brewfiles/Brewfile.ai"
        fi
    fi
    if [ "$feature_macapps" = "true" ]; then
        if brew bundle check --file="$SOURCE_DIR/brewfiles/Brewfile.mac-apps" >/dev/null 2>&1; then
            pass "mac apps Brewfile satisfied"
        else
            warn "Brewfile.mac-apps out of sync — run: brew bundle install --file=$SOURCE_DIR/brewfiles/Brewfile.mac-apps"
        fi
    fi
    case "$profile" in
        personal)
            if brew bundle check --file="$SOURCE_DIR/brewfiles/Brewfile.personal" >/dev/null 2>&1; then
                pass "personal Brewfile satisfied"
            else
                warn "Brewfile.personal out of sync — run: brew bundle install --file=$SOURCE_DIR/brewfiles/Brewfile.personal"
            fi
            ;;
    esac
    case "$profile" in
        work)
            if brew bundle check --file="$SOURCE_DIR/brewfiles/Brewfile.work" >/dev/null 2>&1; then
                pass "work Brewfile satisfied"
            else
                warn "Brewfile.work out of sync — run: brew bundle install --file=$SOURCE_DIR/brewfiles/Brewfile.work"
            fi
            ;;
    esac
    # Drift the OTHER way: ad-hoc installs not tracked anywhere.
    leaves_tmp=$(mktemp)
    brew leaves > "$leaves_tmp" 2>/dev/null || true
    tracked=$(grep -h '^\(brew\|cask\) ' "$SOURCE_DIR"/Brewfile "$SOURCE_DIR"/brewfiles/Brewfile.* 2>/dev/null \
        | sed -E 's/^(brew|cask) "([^"]+)".*/\2/' \
        | awk -F/ '{print $NF}' \
        | sort -u)
    untracked=$(comm -23 <(sort -u "$leaves_tmp") <(echo "$tracked") 2>/dev/null || true)
    rm -f "$leaves_tmp"
    if [ -n "$untracked" ]; then
        n=$(echo "$untracked" | wc -l | tr -d ' ')
        warn "$n brew package(s) installed but not in any Brewfile (run \`chezaudit\` for the list)"
    else
        pass "no untracked brew packages"
    fi
else
    fail "brew not on PATH"
fi

# ─── 7. devbox + direnv (per-project runtimes) ────────────────────────────────
section "devbox + direnv"
if command -v devbox >/dev/null 2>&1; then
    pass "devbox installed: $(devbox version 2>/dev/null | head -1)"
else
    fail "devbox missing — runtimes (Java, Kotlin, Postgres, …) won't activate per project"
fi
# Nix is bootstrapped eagerly by run_onchange_before_01b-install-devbox; verify
# it actually landed. Without /nix, `devbox shell` will halt on a "press enter
# to continue" prompt the first time it runs — that's the paper-cut the eager
# install is meant to prevent.
if [ -d /nix ]; then
    pass "Nix store present at /nix"
    # The LaunchDaemon label depends on which Nix flavour you have:
    #   - Upstream Nix multi-user:  org.nixos.nix-daemon
    #   - Determinate Nix Installer: systems.determinate.nix-daemon
    # We use Determinate via the devbox-bootstrap script, but accept either so
    # this check doesn't flap if/when labels change again or if someone reinstalls
    # with the upstream installer. `sudo launchctl list` lists system daemons.
    if sudo -n launchctl list 2>/dev/null | grep -qE '(org\.nixos|systems\.determinate)\.nix-daemon'; then
        pass "nix-daemon LaunchDaemon running"
    elif launchctl list 2>/dev/null | grep -qE '(org\.nixos|systems\.determinate)\.nix-daemon'; then
        pass "nix-daemon LaunchDaemon running"
    else
        warn "/nix exists but nix-daemon label not found — run \`sudo launchctl list | grep -i nix\` to see what's there. If empty, kickstart with \`sudo launchctl kickstart -k system/systems.determinate.nix-daemon\` (or org.nixos.nix-daemon for upstream Nix)."
    fi
else
    fail "Nix store missing at /nix — devbox will prompt for install on first use. Re-run \`chez\` to bootstrap."
fi
if command -v direnv >/dev/null 2>&1; then
    pass "direnv installed: $(direnv version 2>/dev/null)"
    # Confirm the hook is actually wired into the shell config — without it
    # devbox activation via .envrc is a no-op.
    if grep -q 'direnv hook zsh' "$HOME/.config/zsh/.zshrc" 2>/dev/null; then
        pass "direnv hook present in ~/.config/zsh/.zshrc"
    else
        fail "direnv hook missing from ~/.config/zsh/.zshrc — run: chezmoi apply"
    fi
    if [ -f "$HOME/.config/direnv/direnv.toml" ]; then
        pass "~/.config/direnv/direnv.toml present"
    else
        warn "~/.config/direnv/direnv.toml missing — projects under whitelisted dirs will need per-project \`direnv allow\`"
    fi
else
    fail "direnv missing — .envrc activation won't fire on cd"
fi
# Legacy guard: catch a stale mise install that the user hasn't uninstalled yet.
if command -v mise >/dev/null 2>&1; then
    warn "legacy \`mise\` still on PATH — run: brew uninstall mise && rm -rf ~/.local/share/mise ~/.config/mise"
fi

# ─── 8. Auth state (FYI) ──────────────────────────────────────────────────────
section "Cloud auth (informational)"
if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then pass "gh authenticated"
    else note "gh not authenticated — run when needed: gh auth login"; fi
fi
if command -v az >/dev/null 2>&1; then
    if az account show >/dev/null 2>&1; then pass "az authenticated"
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
        # GKE plugin (only meaningful if gcloud is logged in)
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
    # CRITICAL: `op account list` and `op vault list` are interactive when no
    # accounts are configured — they print a prompt asking if you want to add
    # one. doctor.sh is supposed to be read-only and non-interactive, so we
    # explicitly close stdin with </dev/null. Without this, the next prompt
    # in doctor's flow (or the user's next command) gets ambushed.
    #
    # We also check ~/.config/op/config.json first — if it doesn't exist, op
    # has never been configured and there's nothing to "sign in to". That's
    # the common state when 1Password desktop SSH integration is the only op
    # surface in use (which is our setup).
    if [ -f "$HOME/.config/op/config.json" ] || [ -f "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/Library/Application Support/1Password/Data/op/config.json" ]; then
        if op account list </dev/null >/dev/null 2>&1 && op vault list </dev/null >/dev/null 2>&1; then
            pass "1Password CLI signed in"
        else
            note "1Password CLI not signed in — run if you use op directly: eval \$(op signin)"
        fi
    else
        # No op CLI config at all — that's fine, the SSH agent + git signing
        # path goes through the desktop app, not via `op` directly. No warn.
        pass "1Password CLI not configured (desktop SSH integration is sufficient for this setup)"
    fi
fi

# ─── 9. Fonts ─────────────────────────────────────────────────────────────────
section "Fonts"
if ls "$HOME/Library/Fonts" /Library/Fonts 2>/dev/null | grep -qi 'JetBrainsMono.*Nerd' \
   || ls /opt/homebrew/Caskroom/font-jetbrains-mono-nerd-font 2>/dev/null | grep -q .; then
    pass "JetBrainsMono Nerd Font installed"
else
    warn "JetBrainsMono Nerd Font not found — terminal icons will look broken"
fi

# ─── 10. Privacy permissions hint (can't be checked programmatically) ────────
section "Privacy permissions (manual check)"
echo "  ${DIM}macOS won't let scripts inspect Privacy permissions. Verify manually:${RESET}"
echo "  ${DIM}  System Settings → Privacy & Security →${RESET}"
echo "  ${DIM}    • Full Disk Access:    Ghostty (for protected-dir scans)${RESET}"
echo "  ${DIM}    • Accessibility:       Rectangle, Raycast, Karabiner (if used)${RESET}"
echo "  ${DIM}    • Screen Recording:    Raycast / screenshot tools${RESET}"
echo "  ${DIM}    • Input Monitoring:    Karabiner (if used)${RESET}"
echo "  ${DIM}    • Developer Tools:     your terminal (avoids Gatekeeper friction)${RESET}"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
echo "${BOLD}── Summary ──${RESET}"
echo "  ${GREEN}${PASS} pass${RESET}   ${YELLOW}${ACTION} action${RESET}   ${BLUE}${INFOCOUNT} info${RESET}   ${RED}${FAIL} fail${RESET}"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
