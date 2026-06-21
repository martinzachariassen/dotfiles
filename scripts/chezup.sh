#!/usr/bin/env bash
# chezup.sh — wizard-styled converge flow ("Update repo → Review → Apply").
#
# Invoked by the `chezup` zsh function in dot_config/zsh/dot_zshrc.tmpl; can
# also be run directly:
#   bash ~/Developer/personal/dotfiles/scripts/chezup.sh
#
# Mirrors the install.sh wizard: same banner, same phase headers, same prompt
# helpers — so the bootstrap (`install.sh`) and the daily verb (`chezup`) feel
# like the same product. See docs/lifecycle.md, "Look & feel".
#
# Usage:
#   bash scripts/chezup.sh [chezmoi-apply-args...]
#
# Environment:
#   DRY_RUN=1     print state-changing commands without running them
#   YES=1         skip the confirm gate; apply pending changes automatically
#   DOTFILES_DIR  override the source dir (default: ~/Developer/personal/dotfiles)
#
# Any trailing arguments are passed through to `chezmoi apply`, e.g.
#   bash scripts/chezup.sh -v          # verbose per-file output during apply

set -uo pipefail

SOURCE_DIR="${DOTFILES_DIR:-$HOME/Developer/personal/dotfiles}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${YES:-0}"
export ASSUME_YES # ui.sh's prompt helpers read this

# ─── Shared UI ───────────────────────────────────────────────────────────────
_CHEZUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/ui.sh
if [ ! -r "$_CHEZUP_DIR/lib/ui.sh" ]; then
    printf 'chezup: missing %s\n' "$_CHEZUP_DIR/lib/ui.sh" >&2
    exit 1
fi
# shellcheck source=lib/ui.sh
. "$_CHEZUP_DIR/lib/ui.sh"
ui_init_wizard

# ─── Run / trap ──────────────────────────────────────────────────────────────
run() {
    if [ "$DRY_RUN" = "1" ]; then
        printf "%s    %sdry-run \$%s %s\n" "$(line_prefix)" "$DIM" "$RESET" "$*"
        return 0
    fi
    "$@"
}

on_signal() {
    restore_terminal
    exit 130
}
trap restore_terminal EXIT
trap on_signal INT TERM

# ─── Helpers ─────────────────────────────────────────────────────────────────
human_duration() {
    local secs="$1" mins
    mins=$((secs / 60))
    secs=$((secs % 60))
    printf '%dm%02ds' "$mins" "$secs"
}

# Render a single chezmoi status line as "X path".
#   chezmoi status emits two-column codes (e.g. " M", "A ", "MM"); we collapse
#   them to the first non-space column so the listing reads like the git
#   shorthand most people already recognise.
render_status_line() {
    local line="$1" code path
    code="${line:0:2}"
    path="${line:3}"
    # Pick the first non-space code from the two columns.
    case "$code" in
        ' '*) code="${code:1:1}" ;;
        *) code="${code:0:1}" ;;
    esac
    printf "%s    %s%s%s  %s\n" "$(line_prefix)" "$ACCENT" "$code" "$RESET" "$path"
}

# ─── Phase 1: Update repo ────────────────────────────────────────────────────
phase_update_repo() {
    phase_open "1/3 - Update repo"

    if [ ! -d "$SOURCE_DIR/.git" ]; then
        fail "no git repo at $SOURCE_DIR"
        say "Run install.sh to bootstrap a fresh Mac, or set DOTFILES_DIR."
        exit 1
    fi

    info "git pull --ff-only ${DIM}(in $SOURCE_DIR)${RESET}"
    local before after rc
    before="$(cd "$SOURCE_DIR" && git rev-parse HEAD 2>/dev/null || echo unknown)"
    rc=0
    if [ "$DRY_RUN" = "1" ]; then
        run git -C "$SOURCE_DIR" pull --ff-only
        after="$before"
    else
        (cd "$SOURCE_DIR" && git pull --ff-only) >/dev/null 2>&1 || rc=$?
        after="$(cd "$SOURCE_DIR" && git rev-parse HEAD 2>/dev/null || echo unknown)"
    fi

    if [ "$rc" -ne 0 ]; then
        fail "git pull --ff-only failed (rc=$rc)"
        say "Resolve the divergence in $SOURCE_DIR (e.g. \`git status\`), then re-run chezup."
        exit "$rc"
    fi

    if [ "$before" = "$after" ]; then
        PULLED_COUNT=0
        ok "Up to date (${before:0:7})"
    else
        PULLED_COUNT="$(cd "$SOURCE_DIR" && git rev-list --count "$before..$after" 2>/dev/null || echo '?')"
        ok "Pulled $PULLED_COUNT commit(s) (${before:0:7} → ${after:0:7})"
    fi

    phase_close "Update repo"
}

# ─── Phase 2: Review pending changes ─────────────────────────────────────────
# Sets PENDING_RAW (multi-line chezmoi status output, may be empty) and
# PENDING_COUNT (line count). The Apply phase short-circuits when count is 0.
phase_review() {
    phase_open "2/3 - Review pending changes"

    PENDING_RAW=""
    PENDING_COUNT=0

    if ! command -v chezmoi >/dev/null 2>&1; then
        fail "chezmoi is not on PATH"
        say "Run install.sh first, or \`brew install chezmoi\`."
        exit 1
    fi

    PENDING_RAW="$(chezmoi status --exclude scripts 2>/dev/null || true)"
    if [ -z "$PENDING_RAW" ]; then
        ok "Already in sync — no managed files drifted"
        phase_close "Review pending changes"
        return
    fi

    # Count non-empty lines without `wc | tr` noise.
    PENDING_COUNT=0
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && PENDING_COUNT=$((PENDING_COUNT + 1))
    done <<EOF_COUNT
$PENDING_RAW
EOF_COUNT

    setting "Pending" "$PENDING_COUNT file(s)"
    rule
    while IFS= read -r line; do
        [ -n "$line" ] && render_status_line "$line"
    done <<EOF_LINES
$PENDING_RAW
EOF_LINES
    hr
    dim "    A = add to \$HOME, M = modify, D = remove. Left column is source → \$HOME drift."

    phase_close "Review pending changes"
}

# ─── Phase 3: Apply ──────────────────────────────────────────────────────────
phase_apply() {
    if [ "$PENDING_COUNT" -eq 0 ]; then
        return 0
    fi

    hr
    local proceed
    prompt_confirm proceed "Apply these $PENDING_COUNT change(s)?" 1
    if [ "$proceed" != "true" ]; then
        info "aborted — nothing changed"
        APPLIED_COUNT=0
        return 0
    fi

    phase_open "3/3 - Apply"
    info "chezmoi apply --force ${DIM}${*:-}${RESET}"

    local start_ts end_ts rc=0
    start_ts="$(date +%s)"
    if [ "$DRY_RUN" = "1" ]; then
        run chezmoi apply --force "$@"
    else
        chezmoi apply --force "$@" || rc=$?
    fi
    end_ts="$(date +%s)"

    if [ "$rc" -ne 0 ]; then
        fail "apply failed after $(human_duration $((end_ts - start_ts))) (rc=$rc)"
        exit "$rc"
    fi

    ok "apply finished in $(human_duration $((end_ts - start_ts)))"
    APPLIED_COUNT="$PENDING_COUNT"
    phase_close "Apply"
}

# ─── Done card ───────────────────────────────────────────────────────────────
done_card() {
    local profile mode_chips=""
    profile="$(chezmoi execute-template '{{ .profile }}' 2>/dev/null || true)"
    [ -z "$profile" ] && profile="unknown"

    [ "$DRY_RUN" = "1" ] && mode_chips="${mode_chips}${mode_chips:+ }DRY-RUN"
    [ "$ASSUME_YES" = "1" ] && mode_chips="${mode_chips}${mode_chips:+ }YES"

    printf "%s\n" "$(line_prefix)"
    printf "%s  %sDone%s\n" "$(node_prefix)" "$BOLD" "$RESET"
    if [ "$PENDING_COUNT" -eq 0 ]; then
        say "Your Mac matches the repo."
    elif [ "$APPLIED_COUNT" -gt 0 ]; then
        say "Your Mac matches the repo."
    else
        say "Plan reviewed — no changes applied."
    fi
    rule
    setting "Profile" "$profile"
    setting "Pulled" "${PULLED_COUNT:-0} commit(s)"
    setting "Applied" "${APPLIED_COUNT:-0} file(s)"
    [ -n "$mode_chips" ] && setting "Mode" "$mode_chips"
    printf "%s\n" "$(line_prefix)"
    printf "%s  %schezup complete%s\n\n" "${GREEN}${OK_MARK}${RESET}" "$BOLD" "$RESET"
}

# ─── Main ────────────────────────────────────────────────────────────────────
PULLED_COUNT=0
PENDING_COUNT=0
APPLIED_COUNT=0
PENDING_RAW=""

main() {
    ui_banner "DOTFILES" "converge this Mac" ""
    local chips=""
    [ "$DRY_RUN" = "1" ] && chips="$chips ${YELLOW}${BOLD}[DRY-RUN]${RESET}"
    [ "$ASSUME_YES" = "1" ] && chips="$chips ${YELLOW}${BOLD}[YES]${RESET}"
    [ -n "$chips" ] && printf "%s %s\n" "$(line_prefix)" "$chips"

    hr
    say "Pulls the latest repo, previews drift, then applies — no package upgrades."
    dim "    For brew/mise version bumps run ${BOLD}chezbump${RESET}${DIM}; for a health check run ${BOLD}chezdoctor${RESET}${DIM}."

    phase_update_repo
    phase_review
    phase_apply "$@"
    done_card
}

main "$@"
