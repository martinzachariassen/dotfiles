#!/usr/bin/env bash
# doctor.sh — idempotent read-only health check for the whole stack this repo
# expects (XDG layout, claude config, op signing, brew drift, auth), beyond what
# `chezmoi doctor` covers. Exit 1 on any fail; warnings stay 0.

# Tildes below are display text, not paths — leave them literal.
# shellcheck disable=SC2088
set -uo pipefail

# log.sh is a committed sibling; fail loudly if a checkout is missing it.
_DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ ! -r "$_DOCTOR_DIR/../lib/log.sh" ]; then
    printf 'doctor: missing %s\n' "$_DOCTOR_DIR/../lib/log.sh" >&2
    exit 1
fi
# shellcheck source=../lib/log.sh
. "$_DOCTOR_DIR/../lib/log.sh"
ui_init_status

echo
printf '%s%s%s %sHealth check%s\n' "$BOLD" "$BLUE" "$NODE" "$BOLD" "$RESET"
explain \
    "Checks the repo, Homebrew, auth, signing, runtimes and shell layout." \
    "Read-only: it reports problems and how to fix them, and changes nothing."

PASS=0
ACTION=0
INFOCOUNT=0
FAIL=0

# Thin wrappers over log.sh printers that also bump the summary tallies.
pass() {
    s_pass "$1"
    PASS=$((PASS + 1))
}
warn() {
    s_warn "$1"
    ACTION=$((ACTION + 1))
}
note() {
    s_note "$1"
    INFOCOUNT=$((INFOCOUNT + 1))
}
fail() {
    s_fail "$1"
    FAIL=$((FAIL + 1))
}
section() { s_section "$1"; }

SOURCE_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"

# shellcheck source=../lib/semver.sh
if [ -r "$_DOCTOR_DIR/../lib/semver.sh" ]; then
    . "$_DOCTOR_DIR/../lib/semver.sh"
fi

# shellcheck source=../lib/chezmoi-data.sh
if [ -r "$_DOCTOR_DIR/../lib/chezmoi-data.sh" ]; then
    . "$_DOCTOR_DIR/../lib/chezmoi-data.sh"
fi

# shellcheck source=../lib/vscode.sh
if [ -r "$_DOCTOR_DIR/../lib/vscode.sh" ]; then
    . "$_DOCTOR_DIR/../lib/vscode.sh"
fi

# shellcheck source=../lib/git-signing.sh
if [ -r "$_DOCTOR_DIR/../lib/git-signing.sh" ]; then
    . "$_DOCTOR_DIR/../lib/git-signing.sh"
fi

# shellcheck source=../lib/xcode.sh
if [ -r "$_DOCTOR_DIR/../lib/xcode.sh" ]; then
    . "$_DOCTOR_DIR/../lib/xcode.sh"
fi

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
    if (cd "$SOURCE_DIR" && [ -n "$(git status --porcelain 2>/dev/null)" ]); then
        warn "repo has uncommitted changes — run \`cd $SOURCE_DIR && git status\`"
    else
        pass "repo working tree clean"
    fi
else
    fail "repo missing at $SOURCE_DIR — re-run install.sh"
fi

section "chezmoi"
if command -v chezmoi >/dev/null 2>&1; then
    pass "chezmoi installed: $(chezmoi --version | head -1)"
    if command -v semver_lt >/dev/null 2>&1 && [ -r "$SOURCE_DIR/src/.chezmoiversion" ]; then
        min_ver="$(semver_extract "$(cat "$SOURCE_DIR/src/.chezmoiversion")")"
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
    # Exclude scripts: run_* entries can stay pending after a good apply by design.
    drift=$(chezmoi status --exclude scripts 2>/dev/null | wc -l | tr -d ' ')
    if [ "$drift" = "0" ]; then
        pass "no drift between source and \$HOME"
    else
        warn "$drift file(s) drifted — run \`chezapply\` to apply or \`chezmoi diff\` to inspect"
    fi
else
    fail "chezmoi not installed — re-run install.sh"
fi

section "XDG layout"
for legacy in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.gitconfig" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile"; do
    if [ -f "$legacy" ]; then
        fail "legacy $legacy present — would shadow XDG-managed config. Run \`chezapply\` to remove."
    else
        pass "no legacy $(basename "$legacy")"
    fi
done
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

section "Claude config"
ccdir=$(zsh -c 'source "$HOME/.zshenv" >/dev/null 2>&1; printf %s "${CLAUDE_CONFIG_DIR:-}"')
if [ "$ccdir" = "$HOME/.config/claude" ]; then
    pass "CLAUDE_CONFIG_DIR points at ~/.config/claude"
else
    fail "CLAUDE_CONFIG_DIR is '${ccdir:-unset}' (expected ~/.config/claude) — run: chezmoi apply"
fi
if [ -f "$HOME/.config/claude/CLAUDE.md" ]; then
    pass "~/.config/claude/CLAUDE.md present"
else
    fail "~/.config/claude/CLAUDE.md missing — run: chezmoi apply"
fi

section "Git signing (1Password SSH agent)"
SSH_SIGN="$GIT_SIGNING_SSH_SIGN"
if [ -x "$SSH_SIGN" ]; then
    pass "op-ssh-sign present"
else
    fail "op-ssh-sign missing — install 1Password app and enable SSH agent in Settings → Developer"
fi
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
    if git_signing_smoke_test; then
        pass "git signing works (commit -S succeeded)"
    else
        warn "git -S commit failed — is 1Password unlocked + SSH agent enabled?"
    fi
fi

section "Homebrew packages"
if command -v brew >/dev/null 2>&1; then
    pass "brew installed"
    # Resolves the same Brewfile map as the brew hook; --no-upgrade keeps this a
    # presence check (freshness is chezbump's job).
    data_json="$(cm_data_json)"
    active_files="$(printf '%s' "$data_json" | jq -r '
        (.modules // []) as $mods
        | (.profile // "") as $prof
        | ([.brewfiles.core]
           + (.brewfiles.byModule | to_entries | map(select($mods | index(.key))) | map(.value))
           + ([.brewfiles.byProfile[$prof]] | map(select(. != null))))
        | .[]' 2>/dev/null)"
    if [ -z "$active_files" ]; then
        warn "could not resolve active Brewfiles from chezmoi data"
    else
        while IFS= read -r rel; do
            [ -n "$rel" ] || continue
            f="$SOURCE_DIR/$rel"
            if [ ! -f "$f" ]; then
                warn "Brewfile missing: $rel"
            elif brew bundle check --no-upgrade --file="$f" >/dev/null 2>&1; then
                pass "$rel satisfied"
            else
                warn "$rel out of sync — run: brew bundle install --no-upgrade --file=$f"
            fi
        done <<EOF
$active_files
EOF
    fi
    # Opposite-direction drift: ad-hoc installs not in any Brewfile.
    leaves_tmp=$(mktemp)
    brew leaves >"$leaves_tmp" 2>/dev/null || true
    tracked=$(grep -h '^\(brew\|cask\) ' "$SOURCE_DIR"/packages/Brewfile "$SOURCE_DIR"/packages/Brewfile.* 2>/dev/null |
        sed -E 's/^(brew|cask) "([^"]+)".*/\2/' |
        awk -F/ '{print $NF}' |
        sort -u)
    untracked=$(comm -23 <(sort -u "$leaves_tmp") <(echo "$tracked") 2>/dev/null || true)
    rm -f "$leaves_tmp"
    if [ -n "$untracked" ]; then
        n=$(echo "$untracked" | wc -l | tr -d ' ')
        warn "$n brew package(s) installed but not in any Brewfile (run \`chezstatus\` for the list)"
    else
        pass "no untracked brew packages"
    fi
    # -n previews only (chezmirror runs the real `brew autoremove`); filter out
    # brew's "==>" headers so only formula names count.
    orphans=$(brew autoremove -n 2>/dev/null | grep -vE '^==>' | grep -cE '^[^[:space:]]+$' || true)
    if [ "${orphans:-0}" -gt 0 ]; then
        warn "$orphans orphaned dependency(ies) — run \`chezmirror\` (or \`brew autoremove\`) to prune"
    else
        pass "no orphaned dependencies"
    fi
else
    fail "brew not on PATH"
fi

# Reports both drift directions against the manifest so doctor surfaces what the
# next apply's 03-vscode hook would reconcile.
section "VS Code extensions"
if command -v code >/dev/null 2>&1; then
    vsc_manifest_file="$SOURCE_DIR/packages/vscode-extensions.txt"
    if [ ! -f "$vsc_manifest_file" ]; then
        warn "extension manifest missing: packages/vscode-extensions.txt"
    else
        # Mirrors the 03-vscode hook's locale guard.
        vsc_exclude=()
        if ! cm_has_module "$(cm_data_json)" locale; then
            vsc_exclude=(streetsidesoftware.code-spell-checker-norwegian-bokmal)
        fi
        vsc_installed="$(code --list-extensions 2>/dev/null || true)"
        vsc_manifest="$(vscode_read_manifest "$vsc_manifest_file" ${vsc_exclude[@]+"${vsc_exclude[@]}"})"
        vsc_untracked="$(vscode_untracked "$vsc_installed" "$vsc_manifest")"
        vsc_missing="$(vscode_missing "$vsc_installed" "$vsc_manifest")"
        if [ -z "$vsc_untracked" ] && [ -z "$vsc_missing" ]; then
            pass "all extensions match the manifest"
        else
            if [ -n "$vsc_missing" ]; then
                n=$(printf '%s\n' "$vsc_missing" | wc -l | tr -d ' ')
                warn "$n manifest extension(s) not installed — run: chezmoi apply"
            fi
            if [ -n "$vsc_untracked" ]; then
                n=$(printf '%s\n' "$vsc_untracked" | wc -l | tr -d ' ')
                warn "$n installed extension(s) not in the manifest — \`chezmoi apply\` will prune them (add to packages/vscode-extensions.txt to keep)"
            fi
        fi
    fi
else
    note "VS Code CLI not on PATH — extension check skipped"
fi

section "mise (runtimes)"
if command -v mise >/dev/null 2>&1; then
    pass "mise installed: $(mise version 2>/dev/null | head -1)"
    # Without activation in the shell config mise sets no PATH/JAVA_HOME.
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
    # A missing resolve means the eager `mise install` hook hasn't run yet.
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
    fail "mise missing — language runtimes (java, node, …) won't activate. Run: chezapply"
fi
# Legacy guard: direnv was replaced by mise.
if command -v direnv >/dev/null 2>&1; then
    warn "legacy \`direnv\` still on PATH — no longer used; remove with: brew uninstall direnv && rm -rf ~/.config/direnv"
fi

# Only meaningful with appleDev on. `brew bundle check` above already covers the
# swiftlint/xcodes/sweetpad tier; none of it can build an iOS app, so this
# section checks the Xcode layer underneath — which nothing in an apply installs.
if command -v cm_has_module >/dev/null 2>&1 && cm_has_module "$(cm_data_json)" appleDev; then
    section "Xcode / iOS (appleDev)"
    if ! command -v xcode_ready >/dev/null 2>&1; then
        warn "scripts/lib/xcode.sh missing — Xcode checks skipped"
    elif [ -z "$(xcode_app_path || true)" ]; then
        # One fail, not six: without Xcode.app every check below fails for the
        # same reason, and six red lines read as six problems.
        fail "no Xcode.app — install.sh only installs the Command Line Tools. Run: chezxcode"
    else
        pass "Xcode installed: $(xcode_app_path)"
        if xcode_selected_is_full; then
            pass "active developer dir: $(xcode-select -p)"
        else
            fail "xcode-select points at $(xcode-select -p 2>/dev/null || echo none), not Xcode.app — run: chezxcode"
        fi
        if xcode_build_works; then
            pass "xcodebuild runs: $(xcodebuild -version 2>/dev/null | head -1)"
        elif xcode_license_pending; then
            fail "Xcode licence not accepted — run: chezxcode"
        else
            fail "xcodebuild fails — run: chezxcode"
        fi
        if xcode_first_launch_done; then
            pass "first-launch components installed"
        else
            fail "Xcode first-launch components pending — run: chezxcode"
        fi
        if xcode_has_ios_sdk; then
            pass "iOS Simulator SDK present"
        else
            fail "no iOS Simulator SDK — run: chezxcode"
        fi
        # Separate downloads since Xcode 16, so a complete Xcode routinely has
        # none and every iOS simulator shows as "Unavailable".
        if xcode_has_ios_runtime; then
            pass "iOS simulator runtime: $(xcode_ios_runtimes_summary)"
        else
            fail "no iOS simulator runtime — nothing to run an app on. Run: chezxcode"
        fi
    fi
    for tool in swiftlint swiftformat xcodegen xcode-build-server xcbeautify; do
        if command -v "$tool" >/dev/null 2>&1; then
            pass "$tool on PATH"
        else
            warn "$tool missing — run: chezapply"
        fi
    done
    # SwiftLint doesn't ascend to $HOME, so the config only takes effect when
    # passed with --config; its absence means projects fall back to bare defaults.
    if [ -f "$HOME/.config/swiftlint/config.yml" ]; then
        pass "~/.config/swiftlint/config.yml present"
    else
        warn "~/.config/swiftlint/config.yml missing — run: chezapply"
    fi
    if [ -f "$HOME/.swiftformat" ]; then
        pass "~/.swiftformat present"
    else
        warn "~/.swiftformat missing — run: chezapply"
    fi
fi

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

section "Fonts"
# Glob install locations directly (`ls | grep` mangles non-alphanumeric names).
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

section "Privacy permissions (manual check)"
echo "  ${DIM}macOS won't let scripts inspect Privacy permissions. Verify manually:${RESET}"
echo "  ${DIM}  System Settings ${ARROW_MARK} Privacy & Security ${ARROW_MARK}${RESET}"
echo "  ${DIM}    ${NOTE} Full Disk Access:    Ghostty (for protected-dir scans)${RESET}"
echo "  ${DIM}    ${NOTE} Accessibility:       Rectangle, Raycast, Karabiner (if used)${RESET}"
echo "  ${DIM}    ${NOTE} Screen Recording:    Raycast / screenshot tools${RESET}"
echo "  ${DIM}    ${NOTE} Input Monitoring:    Karabiner (if used)${RESET}"
echo "  ${DIM}    ${NOTE} Developer Tools:     your terminal (avoids Gatekeeper friction)${RESET}"

echo
echo "${BOLD}${RULE} Summary ${RULE}${RESET}"
echo "  ${GREEN}${PASS} pass${RESET}   ${YELLOW}${ACTION} action${RESET}   ${BLUE}${INFOCOUNT} info${RESET}   ${RED}${FAIL} fail${RESET}"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
