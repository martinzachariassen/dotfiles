#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_brew() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# Both directions of package drift: tiers this Mac should have installed, and
# installs no active tier declares. Read through the same brew_active_files
# that the apply hook and chez mirror use, so the three cannot disagree about
# what "tracked" means here.

doctor_brew() {
    section "Homebrew packages"
    if command -v brew >/dev/null 2>&1; then
        pass "brew installed"
        # Resolves the same Brewfile map as the brew hook and as chez mirror's
        # removal set; --no-upgrade keeps this a presence check (freshness is
        # chez bump's job).
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
            done <<<"$active_files"
        fi
        # Opposite-direction drift: installs no ACTIVE tier declares. Same tier set
        # as the check above and as chez mirror, so the two can't disagree about
        # what "tracked" means on this machine.
        tracked_files=()
        while IFS= read -r rel; do
            [ -n "$rel" ] || continue
            [ -f "$SOURCE_DIR/$rel" ] && tracked_files+=("$SOURCE_DIR/$rel")
        done <<<"$active_files"
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
            warn "$n brew package(s) installed but declared by no active Brewfile (run \`chez status\` for the list)"
        else
            pass "no untracked brew packages"
        fi
        # -n previews only (chez mirror runs the real `brew autoremove`); filter out
        # brew's "==>" headers so only formula names count.
        orphans=$(brew autoremove -n 2>/dev/null | grep -vE '^==>' | grep -cE '^[^[:space:]]+$' || true)
        if [ "${orphans:-0}" -gt 0 ]; then
            warn "$orphans orphaned dependency(ies) — run \`chez mirror\` (or \`brew autoremove\`) to prune"
        else
            pass "no orphaned dependencies"
        fi
    else
        fail "brew not on PATH"
    fi

    # Reports both drift directions against the manifest so doctor surfaces what the
    # next apply's 03-vscode hook would reconcile.
}
