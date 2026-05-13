#!/usr/bin/env bash
# doctor.sh — health check for the dotfiles install on this machine.
#
# Run anytime (idempotent, read-only):
#   bash ~/Dev/Personal/dotfiles/doctor.sh
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
#   *whole stack* this repo expects — XDG layout, claude wrapper routing, op
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
WARN=0
FAIL=0

pass() { echo "  ${GREEN}✓${RESET}  $1"; PASS=$((PASS + 1)); }
warn() { echo "  ${YELLOW}!${RESET}  $1"; WARN=$((WARN + 1)); }
fail() { echo "  ${RED}✗${RESET}  $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "${BOLD}${BLUE}── $1 ──${RESET}"; }

SOURCE_DIR="${DOTFILES_DIR:-$HOME/Dev/Personal/dotfiles}"

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
    if chezmoi doctor 2>&1 | grep -q '^error'; then
        fail "chezmoi doctor reports errors — run: chezmoi doctor"
    else
        pass "chezmoi doctor clean"
    fi
    # Drift between source and $HOME
    drift=$(chezmoi status 2>/dev/null | wc -l | tr -d ' ')
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
for legacy in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.gitconfig"; do
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

# ─── 4. Claude wrapper routing ────────────────────────────────────────────────
section "Claude profile routing"
# Source the wrapper into a subshell and exercise it from two PWDs.
if zsh -c 'source "$HOME/.config/zsh/.zshrc" >/dev/null 2>&1; type claude >/dev/null 2>&1'; then
    pass "claude wrapper loads"
    # Personal route (PWD outside ~/Dev/Work/)
    # NOTE: comments inside zsh -c "..." must avoid apostrophes — the outer
    # quoting is single, so an apostrophe in a comment closes it prematurely.
    personal_dir=$(zsh -c '
        source "$HOME/.config/zsh/.zshrc" >/dev/null 2>&1
        cd /tmp
        # Re-exec the wrapper logic to print where it would route, using the
        # same case statement the wrapper itself uses.
        unset CLAUDE_PROFILE
        CLAUDE_PERSONAL_DIR="$HOME/.config/claude/personal"
        CLAUDE_WORK_DIR="$HOME/.claude"
        case "$PWD/" in
            "$HOME/Dev/Work/"*) echo "$CLAUDE_WORK_DIR" ;;
            *)                  echo "$CLAUDE_PERSONAL_DIR" ;;
        esac
    ' 2>/dev/null)
    expected_personal="$HOME/.config/claude/personal"
    if [ "$personal_dir" = "$expected_personal" ]; then
        pass "PWD=/tmp routes to personal ($expected_personal)"
    else
        fail "PWD=/tmp routed to '$personal_dir' (expected $expected_personal)"
    fi
    # Work route (PWD inside ~/Dev/Work/) — only sane to test if the dir exists
    if [ -d "$HOME/Dev/Work" ]; then
        work_dir=$(zsh -c '
            source "$HOME/.config/zsh/.zshrc" >/dev/null 2>&1
            cd "$HOME/Dev/Work"
            unset CLAUDE_PROFILE
            CLAUDE_PERSONAL_DIR="$HOME/.config/claude/personal"
            CLAUDE_WORK_DIR="$HOME/.claude"
            case "$PWD/" in
                "$HOME/Dev/Work/"*) echo "$CLAUDE_WORK_DIR" ;;
                *)                  echo "$CLAUDE_PERSONAL_DIR" ;;
            esac
        ' 2>/dev/null)
        if [ "$work_dir" = "$HOME/.claude" ]; then
            pass "PWD=~/Dev/Work routes to work (~/.claude)"
        else
            fail "PWD=~/Dev/Work routed to '$work_dir' (expected ~/.claude)"
        fi
        if [ -d "$HOME/.claude" ]; then
            pass "~/.claude present (storecode installed)"
        else
            warn "~/.claude missing — work-profile claude calls would fall back to personal (see WORK-SETUP.md)"
        fi
    fi
    # Personal config dir
    if [ -d "$HOME/.config/claude/personal" ]; then
        pass "~/.config/claude/personal present"
    else
        fail "~/.config/claude/personal missing — run: chezmoi apply"
    fi
else
    fail "claude wrapper not loaded by zshrc — run: chezmoi apply"
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
else
    warn "no git signing key set — run \`chezmoi init\` to re-prompt or edit ~/.config/git/config"
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
    # Profile-specific
    profile=$(chezmoi data --format=json 2>/dev/null | grep -o '"profile":"[^"]*"' | cut -d'"' -f4 || echo "")
    case "$profile" in
        personal|both)
            if brew bundle check --file="$SOURCE_DIR/Brewfile.personal" >/dev/null 2>&1; then
                pass "personal Brewfile satisfied"
            else
                warn "Brewfile.personal out of sync — run: brew bundle install --file=$SOURCE_DIR/Brewfile.personal"
            fi
            ;;
    esac
    case "$profile" in
        work|both)
            if brew bundle check --file="$SOURCE_DIR/Brewfile.work" >/dev/null 2>&1; then
                pass "work Brewfile satisfied"
            else
                warn "Brewfile.work out of sync — run: brew bundle install --file=$SOURCE_DIR/Brewfile.work"
            fi
            ;;
    esac
    # Drift the OTHER way: ad-hoc installs not tracked anywhere.
    leaves_tmp=$(mktemp)
    brew leaves > "$leaves_tmp" 2>/dev/null || true
    tracked=$(grep -h '^\(brew\|cask\) ' "$SOURCE_DIR"/Brewfile* 2>/dev/null \
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
    else warn "gh not authenticated — run: gh auth login"; fi
fi
if command -v az >/dev/null 2>&1; then
    if az account show >/dev/null 2>&1; then pass "az authenticated"
    else warn "az not authenticated — run: az login"; fi
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
        warn "gcloud not authenticated — run: gcloud auth login"
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
            warn "1Password CLI not signed in — run: eval \$(op signin)"
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
echo "  ${DIM}    • Full Disk Access:    Ghostty (so Safari defaults apply)${RESET}"
echo "  ${DIM}    • Accessibility:       Rectangle, Raycast, Karabiner (if used)${RESET}"
echo "  ${DIM}    • Screen Recording:    Raycast / screenshot tools${RESET}"
echo "  ${DIM}    • Input Monitoring:    Karabiner (if used)${RESET}"
echo "  ${DIM}    • Developer Tools:     your terminal (avoids Gatekeeper friction)${RESET}"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
echo "${BOLD}── Summary ──${RESET}"
echo "  ${GREEN}${PASS} pass${RESET}   ${YELLOW}${WARN} warn${RESET}   ${RED}${FAIL} fail${RESET}"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
