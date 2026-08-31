#!/usr/bin/env bash
# A sourced fragment, not a script: it defines doctor_runtimes() and nothing else.
# features/doctor/cli.sh sources it and calls it, so it can use that runner's
# pass/warn/note/fail helpers and keep the tallies in one process.
#
# mise itself, its activation in the shell config, and whether the runtimes it
# declares actually resolve. Activation is the one that bites: without it mise
# sets no PATH and no JAVA_HOME, and nothing says so.

doctor_runtimes() {
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
        fail "mise missing — language runtimes (java, node, …) won't activate. Run: chez apply"
    fi
    # Legacy guard: direnv was replaced by mise.
    if command -v direnv >/dev/null 2>&1; then
        warn "legacy \`direnv\` still on PATH — no longer used; remove with: brew uninstall direnv && rm -rf ~/.config/direnv"
    fi
}
