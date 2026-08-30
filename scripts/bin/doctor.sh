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

# shellcheck source=../lib/brewfiles.sh
if [ -r "$_DOCTOR_DIR/../lib/brewfiles.sh" ]; then
    . "$_DOCTOR_DIR/../lib/brewfiles.sh"
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

# shellcheck source=../lib/distill.sh
if [ -r "$_DOCTOR_DIR/../lib/distill.sh" ]; then
    . "$_DOCTOR_DIR/../lib/distill.sh"
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

# Read once here; the signing, locale, appleDev and Homebrew sections all key
# off it. chezmoi-data.sh is sourced conditionally above, so degrade to empty
# data rather than dying on a missing helper.
if command -v cm_data_json >/dev/null 2>&1; then
    DATA_JSON="$(cm_data_json)"
    SIGNING_MODE="$(cm_data_string "$DATA_JSON" "signingMode")"
else
    DATA_JSON='{}'
    SIGNING_MODE=""
fi

# ─── Commit author ───────────────────────────────────────────────────────────
# Checked before signing, because an unsigned commit is a preference and an
# unattributed one is a mistake. Setup allows a blank email (the address is
# usually a GitHub noreply nobody remembers on install day) — this is what makes
# that state visible rather than silent.
section "Commit author"
git_email="$(git config --global user.email 2>/dev/null || true)"
git_name="$(git config --global user.name 2>/dev/null || true)"
if [ -n "$git_email" ]; then
    pass "git author: ${git_name:-?} <$git_email>"
elif [ "$(git config --global user.useConfigOnly 2>/dev/null || true)" = "true" ]; then
    fail "no git email set — commits are blocked. Run \`chezsetup\` to add one"
    note "GitHub noreply address: github.com → Settings → Emails"
else
    fail "no git email set, and nothing stops git inventing one — run \`chezsetup\`"
fi

section "Git signing (${SIGNING_MODE:-1password})"
SSH_SIGN="${GIT_SIGNING_SSH_SIGN:-}"
if [ "$SIGNING_MODE" = "off" ]; then
    note "signing disabled in setup (signingMode = off) — nothing to check"
elif [ "$SIGNING_MODE" = "ssh-key" ]; then
    note "signing uses a plain SSH key (signingMode = ssh-key), not the 1Password agent"
elif [ -z "$SSH_SIGN" ]; then
    warn "scripts/lib/git-signing.sh not readable — skipping the signing checks"
elif [ -x "$SSH_SIGN" ]; then
    pass "op-ssh-sign present"
else
    fail "op-ssh-sign missing — install 1Password app and enable SSH agent in Settings → Developer"
fi
gitkey=$(git config --global user.signingkey 2>/dev/null || true)
if [ "$SIGNING_MODE" = "off" ]; then
    : # nothing configured by design
elif [ -n "$gitkey" ]; then
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
    # gpg.ssh.program is emitted only for signingMode = 1password (see
    # src/dot_config/git/config.tmpl); under ssh-key it is absent by design.
    if [ "$SIGNING_MODE" = "ssh-key" ]; then
        note "gpg.ssh.program not set — correct for signingMode = ssh-key"
    elif [ "$(git config --global gpg.ssh.program 2>/dev/null || true)" = "$SSH_SIGN" ]; then
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
# 1password mode only: the other modes have no agent to reach.
if [ "$SIGNING_MODE" != "ssh-key" ] && [ "$SIGNING_MODE" != "off" ] &&
    [ -n "$SSH_SIGN" ] && [ -x "$SSH_SIGN" ] && [ -n "$gitkey" ]; then
    if git_signing_smoke_test; then
        pass "git signing works (commit -S succeeded)"
    else
        warn "git -S commit failed — is 1Password unlocked + SSH agent enabled?"
    fi
fi

section "Homebrew packages"
if command -v brew >/dev/null 2>&1; then
    pass "brew installed"
    # Resolves the same Brewfile map as the brew hook and as chezmirror's
    # removal set; --no-upgrade keeps this a presence check (freshness is
    # chezbump's job).
    active_files="$(brew_active_files "$DATA_JSON" 2>/dev/null)"
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
    # Opposite-direction drift: installs no ACTIVE tier declares. Same tier set
    # as the check above and as chezmirror, so the two can't disagree about
    # what "tracked" means on this machine.
    tracked_files=()
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        [ -f "$SOURCE_DIR/$rel" ] && tracked_files+=("$SOURCE_DIR/$rel")
    done <<EOF
$active_files
EOF
    # Guard the empty case explicitly: a bare `grep -h PATTERN` with no file
    # operands reads stdin and would hang this check forever.
    if [ "${#tracked_files[@]}" -eq 0 ]; then
        warn "could not resolve the active Brewfiles — skipping the untracked-package check"
        untracked=""
    else
        leaves_tmp=$(mktemp)
        brew leaves >"$leaves_tmp" 2>/dev/null || true
        tracked=$(grep -h '^\(brew\|cask\) ' "${tracked_files[@]}" 2>/dev/null |
            sed -E 's/^(brew|cask) "([^"]+)".*/\2/' |
            awk -F/ '{print $NF}' |
            sort -u)
        untracked=$(comm -23 <(sort -u "$leaves_tmp") <(echo "$tracked") 2>/dev/null || true)
        rm -f "$leaves_tmp"
    fi
    if [ -n "$untracked" ]; then
        n=$(echo "$untracked" | wc -l | tr -d ' ')
        warn "$n brew package(s) installed but declared by no active Brewfile (run \`chezstatus\` for the list)"
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
        if ! cm_has_module "$DATA_JSON" locale; then
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

# ~/.config/cspell/personal.txt is a symlink *into this repo*, so it is the one
# managed path a repo-side file move can break. cSpell fails silently when the
# dictionary is unreadable — it just stops knowing the words — so nothing else
# would ever report it.
cspell_link="$HOME/.config/cspell/personal.txt"
if [ -L "$cspell_link" ]; then
    if [ -r "$cspell_link" ]; then
        pass "cSpell personal dictionary resolves"
    else
        fail "cSpell dictionary is a dangling symlink: $(readlink "$cspell_link") — run: chezmoi apply"
    fi
elif [ -e "$cspell_link" ]; then
    warn "$cspell_link is not a symlink — chezmoi expects to manage it; run: chezmoi apply"
else
    note "cSpell personal dictionary not deployed yet — run: chezmoi apply"
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
if command -v cm_has_module >/dev/null 2>&1 && cm_has_module "$DATA_JSON" appleDev; then
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

# chezdistill has no human-facing output by design — the reports it used to write
# into an Obsidian vault were removed. That took away the one passive signal that
# the nightly job was still alive: if the launchd agent is gone, or the Mac was
# off for a fortnight, MAIN.md simply stops growing and nothing says so. This
# section is that signal. `chezdistill --status` has the detail; this answers only
# "is it still running", which is the question you never think to ask.
if command -v cm_has_module >/dev/null 2>&1 && cm_has_module "$DATA_JSON" claudeDistiller; then
    section "Claude memory (claudeDistiller)"
    if ! command -v distill_last_run >/dev/null 2>&1; then
        warn "scripts/lib/distill.sh missing — chezdistill checks skipped"
    else
        if [ "$(uname -s)" = "Darwin" ]; then
            if launchctl print "gui/$(id -u)/no.mlz.chezdistill.nightly" >/dev/null 2>&1; then
                pass "nightly agent registered (01:00)"
            else
                fail "nightly agent not registered — nothing distils. Run: chezdistill --setup"
            fi
        fi

        # Are there any inputs? Every other check here is on the output side, and
        # that is how a job whose transcriptRoots pointed at a directory that has
        # never existed passed this whole section, green, every day of its life:
        # registered, ran, wrote a MAIN.md, backed the corpus up — and read
        # nothing. "Could it have worked" is not "did it work".
        distill_sources=0
        while IFS= read -r distill_root; do
            [ -n "$distill_root" ] || continue
            distill_sources=$((distill_sources + $(distill_source_count "$distill_root")))
        done < <(distill_source_roots 2>/dev/null)
        if [ "$distill_sources" -eq 0 ]; then
            fail "no transcripts under any transcriptRoot — nothing can be distilled. See: chezdistill --status"
        else
            pass "$distill_sources transcript(s) to read from"
        fi

        distill_last="$(distill_last_run 2>/dev/null || true)"
        if [ -z "$distill_last" ]; then
            note "no run recorded yet — backfill with: chezdistill --since 7d"
        else
            distill_when="$(printf '%s' "$distill_last" | jq -r '.end // .t' 2>/dev/null)"
            distill_age="$(distill_days_since "$distill_when" 2>/dev/null || echo 0)"
            distill_verdict="$(printf '%s' "$distill_last" | jq -r '.status' 2>/dev/null)"
            if [ "$distill_verdict" != "ok" ]; then
                fail "last run failed ($(printf '%s' "$distill_when" | cut -c1-10)) — see: chezdistill --status"
            elif [ "${distill_age:-0}" -gt 3 ]; then
                warn "last run was ${distill_age} days ago — the timer may not be firing. See: chezdistill --status"
            else
                pass "last run ${distill_age} day(s) ago, ok"
            fi
            # Succeeded, and opened nothing, while transcripts sit there unread.
            # The exact shape of the transcriptRoots bug, and of the next thing
            # that quietly stops the harvester reaching the files.
            if [ "$distill_verdict" = "ok" ] && [ "$distill_sources" -gt 0 ] &&
                [ "$(printf '%s' "$distill_last" | jq -r '.sessions.seen // 0')" = "0" ]; then
                warn "the last run read 0 of $distill_sources transcript(s) — see: chezdistill --runs"
            fi
        fi

        distill_main="$(distill_memory_dir)/MAIN.md"
        if [ -f "$distill_main" ]; then
            pass "MAIN.md present: $(wc -c <"$distill_main" | tr -d ' ')B of $(distill_cfg mainCapBytes 6144)B"
        else
            warn "MAIN.md not rendered — the persona imports nothing. Run: chezdistill --render"
        fi

        # A corpus with no remote is one disk failure from gone, and it is the
        # only thing here that cannot be regenerated. Worse than no remote is the
        # other profile's remote: it looks like a backup, and it isn't — it is
        # work memory promoted into personal sessions, one push past undoing.
        # Whether it is REACHING the remote, not merely which remote it names.
        # This line used to pass on the strength of an origin URL existing, so a
        # push that had been rejected every night for two days still read green.
        # The verdict is computed once, in distill_backup_state, and only
        # rendered here — chezdistill --status renders the same one.
        if ! distill_corpus_check_local >/dev/null 2>&1; then
            fail "the corpus is stamped $(distill_corpus_profile) but this is a $(distill_profile) Mac. See: chezdistill --status"
        else
            distill_url="$(git -C "$(distill_state_dir)" remote get-url origin 2>/dev/null || true)"
            read -r distill_bv distill_bn _ <<<"$(distill_backup_state 2>/dev/null)"
            case "$distill_bv" in
                no-repo) note "no corpus repo yet — the first run creates it" ;;
                no-remote) warn "corpus is local only — this Mac is the only copy. Attach one: chezdistill --remote <url>" ;;
                wedged) fail "the corpus repo is stuck mid-operation — nothing is being pushed. See: chezdistill --status" ;;
                no-upstream) fail "corpus has never reached $distill_url. See: chezdistill --status" ;;
                ahead) warn "$distill_bn corpus commit(s) not yet on $distill_url. See: chezdistill --status" ;;
                behind) warn "corpus is $distill_bn commit(s) behind $distill_url — the next run catches up" ;;
                diverged) fail "corpus has diverged from $distill_url. See: chezdistill --status" ;;
                *) pass "corpus backed up to $distill_url" ;;
            esac
        fi
    fi
fi

# Containers. The failure that actually bites is silent: colima's home follows
# $XDG_CONFIG_HOME only while ~/.colima is absent, so anything that starts it
# without that variable strands the managed template and every later shell with
# it. Cheap to check, invisible otherwise.
section "Containers (colima)"
if command -v colima >/dev/null 2>&1; then
    if [ -d "$HOME/.colima" ]; then
        fail "~/.colima shadows ~/.config/colima — the managed VM template is ignored. Fix: colima delete && rm -rf ~/.colima && chezapply"
    else
        pass "colima home is ~/.config/colima"
    fi
    if [ "$(uname -s)" = "Darwin" ]; then
        if launchctl print "gui/$(id -u)/no.mlz.colima" >/dev/null 2>&1; then
            pass "login agent registered"
        else
            warn "colima login agent not registered — the VM won't start at login. Run: chezapply"
        fi
    fi
    if colima status >/dev/null 2>&1; then
        pass "VM running"
        if docker info >/dev/null 2>&1; then
            pass "docker talks to the VM ($(docker context show 2>/dev/null) context)"
        else
            fail "docker cannot reach the daemon despite a running VM — check: colima status"
        fi
    else
        note "colima VM stopped — start it with: colima start"
    fi
    # Homebrew installs the plugins outside the CLI's search path; without the
    # managed symlinks `docker compose` is simply an unknown command.
    for plugin in docker-compose docker-buildx; do
        if [ -e "$HOME/.docker/cli-plugins/$plugin" ]; then
            pass "$plugin plugin linked"
        else
            warn "$plugin not linked into ~/.docker/cli-plugins — run: chezapply"
        fi
    done
else
    fail "colima missing — there is no container runtime on this Mac. Run: chezapply"
fi
# Legacy guard: Docker Desktop was replaced by colima.
if [ -d "/Applications/Docker.app" ]; then
    warn "Docker Desktop still installed — it fights colima over ~/.docker. Remove with: brew uninstall --cask docker-desktop"
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
