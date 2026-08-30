#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_check_chezmoi() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# chezmoi itself: the binary, its version, its generated config, and whether
# the source path it believes in matches the repo the check above found.

doctor_check_chezmoi() {
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
}
