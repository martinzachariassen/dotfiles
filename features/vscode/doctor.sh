#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_vscode() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# Extension drift in both directions, read through the same lib.sh the apply
# hook mirrors with — so the report and the apply cannot disagree.

doctor_vscode() {
    section "VS Code extensions"
    if command -v code >/dev/null 2>&1; then
        vsc_manifest_file="$SOURCE_DIR/features/vscode/extensions.txt"
        if [ ! -f "$vsc_manifest_file" ]; then
            warn "extension manifest missing: features/vscode/extensions.txt"
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
                    warn "$n installed extension(s) not in the manifest — \`chezmoi apply\` will prune them (add to features/vscode/extensions.txt to keep)"
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
}
