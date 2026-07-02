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

# Tilde in the user-facing status strings throughout this script is intentional
# — those are display messages, not paths passed to commands, so they stay
# literal. File-level disable must precede the first command below.
# shellcheck disable=SC2088
set -uo pipefail

# ─── Color + shared helpers ───────────────────────────────────────────────────
# Loaded from next to this script so they work even when DOTFILES_DIR is
# overridden or the script is invoked from another directory.
_DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/ui.sh
if [ -r "$_DOCTOR_DIR/lib/ui.sh" ]; then
    . "$_DOCTOR_DIR/lib/ui.sh"
    ui_init_colors
    ui_init_glyphs
else
    BOLD=""
    DIM=""
    GREEN=""
    YELLOW=""
    BLUE=""
    RED=""
    RESET=""
    # ui.sh unavailable — define ASCII glyphs so status marks never print as
    # mojibake on a non-UTF-8 locale (the whole point of ui_init_glyphs).
    OK_MARK="OK"
    FAIL_MARK="X"
    ARROW_MARK=">"
    NOTE="-"
    RULE="--"
fi

PASS=0
ACTION=0
INFOCOUNT=0
FAIL=0

pass() {
    echo "  ${GREEN}${OK_MARK}${RESET}  $1"
    PASS=$((PASS + 1))
}
warn() {
    echo "  ${YELLOW}!${RESET}  $1"
    ACTION=$((ACTION + 1))
}
note() {
    echo "  ${BLUE}${NOTE}${RESET}  $1"
    INFOCOUNT=$((INFOCOUNT + 1))
}
fail() {
    echo "  ${RED}${FAIL_MARK}${RESET}  $1"
    FAIL=$((FAIL + 1))
}
section() {
    echo
    echo "${BOLD}${BLUE}${RULE} $1 ${RULE}${RESET}"
}

SOURCE_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"

# Shared semver helpers (semver_extract / semver_lt) for the chezmoi
# version-minimum check below. Same script-relative dir resolved above.
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
if [ -f "$HOME/.config/claude/CLAUDE.md" ]; then
    pass "~/.config/claude/CLAUDE.md present (base + active profile)"
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
        feature_macapps="$(printf '%s\n' "$data_json" | jq -r '.features.macApps // true')"
    else
        profile="$(printf '%s\n' "$data_json" | sed -n 's/.*"profile"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tail -1)"
        feature_macapps="$(printf '%s\n' "$data_json" | sed -n 's/.*"macApps"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | tail -1)"
        feature_macapps="${feature_macapps:-true}"
    fi
    if [ "$feature_macapps" = "true" ]; then
        if brew bundle check --file="$SOURCE_DIR/brewfiles/Brewfile.mac-apps" >/dev/null 2>&1; then
            pass "mac apps Brewfile satisfied"
        else
            warn "Brewfile.mac-apps out of sync — run: brew bundle install --file=$SOURCE_DIR/brewfiles/Brewfile.mac-apps"
        fi
        # Ollama ships in the mac-apps module and runs as a brew service
        # (models are pulled manually).
        if command -v ollama >/dev/null 2>&1; then
            if brew services list 2>/dev/null | grep -E '^ollama[[:space:]]' | grep -q started; then
                pass "Ollama service running"
            else
                warn "Ollama service not started — run: scripts/setup-ollama.sh"
            fi
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
    brew leaves >"$leaves_tmp" 2>/dev/null || true
    tracked=$(grep -h '^\(brew\|cask\) ' "$SOURCE_DIR"/Brewfile "$SOURCE_DIR"/brewfiles/Brewfile.* 2>/dev/null |
        sed -E 's/^(brew|cask) "([^"]+)".*/\2/' |
        awk -F/ '{print $NF}' |
        sort -u)
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

# ─── 7. mise (language runtimes) ──────────────────────────────────────────────
section "mise (runtimes)"
if command -v mise >/dev/null 2>&1; then
    pass "mise installed: $(mise version 2>/dev/null | head -1)"
    # Confirm activation is wired into the shell config — without it mise
    # doesn't set PATH/JAVA_HOME or auto-switch per project.
    if grep -q 'mise activate zsh' "$HOME/.config/zsh/.zshrc" 2>/dev/null; then
        pass "mise activation present in ~/.config/zsh/.zshrc"
    else
        fail "mise activation missing from ~/.config/zsh/.zshrc — run: chezmoi apply"
    fi
    if [ -f "$HOME/.config/mise/config.toml" ]; then
        pass "~/.config/mise/config.toml present"
    else
        warn "~/.config/mise/config.toml missing — no global java/node defaults; run: chezmoi apply"
    fi
    # Verify the global runtimes actually resolved to an installed path. A
    # missing install means the eager `mise install` (run_onchange_after_02b)
    # hasn't run yet — first shell would have no java/node.
    if mise where java >/dev/null 2>&1; then
        pass "java resolves: $(mise where java 2>/dev/null)"
    else
        warn "java not installed via mise — run: mise install"
    fi
    if mise where node >/dev/null 2>&1; then
        pass "node resolves: $(mise where node 2>/dev/null)"
    else
        warn "node not installed via mise — run: mise install"
    fi
else
    fail "mise missing — language runtimes (java, node, …) won't activate. Run: chez"
fi
# Legacy guards: catch leftovers from the old devbox + direnv + Nix stack.
if command -v devbox >/dev/null 2>&1; then
    warn "legacy \`devbox\` still on PATH — uninstall: rm -f /usr/local/bin/devbox (runtimes now come from mise)"
fi
if [ -d /nix ]; then
    warn "legacy Nix store still at /nix — devbox is gone; uninstall with \`/nix/nix-installer uninstall\` if you want the space back"
fi
if command -v direnv >/dev/null 2>&1; then
    warn "legacy \`direnv\` still on PATH — no longer used; remove with: brew uninstall direnv && rm -rf ~/.config/direnv"
fi

# ─── 8. Auth state (FYI) ──────────────────────────────────────────────────────
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
# Glob the install locations directly (avoids `ls | grep`, which mangles
# non-alphanumeric names). The Caskroom path proves the cask is installed even
# if the font files live elsewhere.
jetbrains_nerd_font_installed() {
    local f
    for f in "$HOME/Library/Fonts"/JetBrainsMono*Nerd* \
        /Library/Fonts/JetBrainsMono*Nerd* \
        /opt/homebrew/Caskroom/font-jetbrains-mono-nerd-font/*; do
        [ -e "$f" ] && return 0
    done
    return 1
}
if jetbrains_nerd_font_installed; then
    pass "JetBrainsMono Nerd Font installed"
else
    warn "JetBrainsMono Nerd Font not found — terminal icons will look broken"
fi

# ─── 10. Privacy permissions hint (can't be checked programmatically) ────────
section "Privacy permissions (manual check)"
echo "  ${DIM}macOS won't let scripts inspect Privacy permissions. Verify manually:${RESET}"
echo "  ${DIM}  System Settings ${ARROW_MARK} Privacy & Security ${ARROW_MARK}${RESET}"
echo "  ${DIM}    ${NOTE} Full Disk Access:    Ghostty (for protected-dir scans)${RESET}"
echo "  ${DIM}    ${NOTE} Accessibility:       Rectangle, Raycast, Karabiner (if used)${RESET}"
echo "  ${DIM}    ${NOTE} Screen Recording:    Raycast / screenshot tools${RESET}"
echo "  ${DIM}    ${NOTE} Input Monitoring:    Karabiner (if used)${RESET}"
echo "  ${DIM}    ${NOTE} Developer Tools:     your terminal (avoids Gatekeeper friction)${RESET}"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
echo "${BOLD}${RULE} Summary ${RULE}${RESET}"
echo "  ${GREEN}${PASS} pass${RESET}   ${YELLOW}${ACTION} action${RESET}   ${BLUE}${INFOCOUNT} info${RESET}   ${RED}${FAIL} fail${RESET}"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
