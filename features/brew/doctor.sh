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
        # The resolver has one refusal that is not a broken checkout and not a
        # missing jq: a config still carrying the retired `profile` key, which
        # it will not resolve a tier set for. Named separately because the
        # generic message sends you looking for the wrong fault, and because
        # this one has a one-line fix.
        if printf '%s' "$DATA_JSON" | jq -e 'has("profile")' >/dev/null 2>&1; then
            fail "this Mac's chezmoi config still has the retired \`profile\` key — run \`chez up\` once to migrate it"
        elif [ -z "$active_files" ]; then
            warn "could not resolve active Brewfiles from chezmoi data"
        else
            while IFS= read -r rel; do
                [ -n "$rel" ] || continue
                f="$(brew_resolve_file "$SOURCE_DIR" "$rel")"
                if [ -z "$f" ]; then
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
            abs="$(brew_resolve_file "$SOURCE_DIR" "$rel")"
            [ -n "$abs" ] && tracked_files+=("$abs")
        done <<<"$active_files"
        # Guard the empty case explicitly: brew_untracked_of_kind refuses a
        # zero-length file list, and comparing against too FEW tiers would call
        # most of the machine untracked.
        n_formulae=0
        n_casks=0
        if [ "${#tracked_files[@]}" -eq 0 ]; then
            warn "could not resolve the active Brewfiles — skipping the untracked-package check"
        else
            # Both directions, both namespaces. Casks used to be invisible here:
            # the installed side was `brew leaves` alone, which lists formulae
            # only, so an undeclared cask sat unreported while chez status and
            # chez mirror — which read through brew bundle cleanup — both saw it.
            untracked_formulae=$(brew_untracked_of_kind brew \
                "$(brew leaves 2>/dev/null)" "${tracked_files[@]}")
            # `brew leaves` deliberately hides formulae that exist only as
            # someone else's dependency; those are the orphan check's business,
            # below. Casks have no such notion — every installed cask is
            # top-level — so the whole list is the installed side.
            untracked_casks=$(brew_untracked_of_kind cask \
                "$(brew list --cask 2>/dev/null)" "${tracked_files[@]}")
            # grep -c over an unterminated string still counts its last line and
            # yields 0 for the empty one, which `wc -l` would report as 1.
            n_formulae=$(printf '%s' "$untracked_formulae" | grep -c . || true)
            n_casks=$(printf '%s' "$untracked_casks" | grep -c . || true)
        fi
        n=$((n_formulae + n_casks))
        if [ "$n" -gt 0 ]; then
            warn "$n brew package(s) installed but declared by no active Brewfile ($n_formulae formula(e), $n_casks cask(s)) — run \`chez status\` for the list"
        else
            pass "no untracked brew packages"
        fi
        # The overlay is machine-local and outside the checkout, so it appears in
        # no diff and no `git status`. Doctor is the only place it ever surfaces.
        # Staying quiet about it would let an adopted package read as a repo
        # package — the one thing this whole mechanism must not blur.
        #
        # Silent when it declares nothing: install seeds the file on every Mac,
        # so its mere existence says nothing, and "0 package(s) kept only on
        # this Mac" would be a line every machine prints forever.
        overlay="$(chez_local_brewfile)"
        n_local=0
        if [ -f "$overlay" ]; then
            n_local=$(grep -cE '^[[:space:]]*(brew|cask|tap|mas|vscode) ' "$overlay" 2>/dev/null || true)
        fi
        if [ "${n_local:-0}" -gt 0 ]; then
            note "$n_local package(s) kept only on this Mac — ${overlay/#$HOME/\~}"
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
