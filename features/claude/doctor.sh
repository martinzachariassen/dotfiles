#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_claude() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# The persona, the settings and the status line — chezmoi-deployed files, so
# what is worth checking is that they arrived and are addressable.

doctor_claude() {
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
}
