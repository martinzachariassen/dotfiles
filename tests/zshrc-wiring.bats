#!/usr/bin/env bats
# Pin the critical tool activations and env-var wiring in the managed shell.
#
# Why this exists:
#   `render-check.sh` runs `zsh -n` on the rendered zshrc, which catches
#   parse errors — not silent deletes. If the line `eval "$(mise activate
#   zsh)"` gets removed by accident, the file still parses, but `cd` into a
#   project no longer switches Java/Node versions and `JAVA_HOME` no longer
#   points at the JDK mise installed. Same for starship (no prompt),
#   zoxide (no `z`), fzf (no Ctrl-R), and the XDG/CLAUDE_CONFIG_DIR exports
#   in zshenv. doctor.sh catches some of this at runtime, but only on a
#   machine that's actually applied the latest source.
#
# We grep the templates directly. Go-template directives don't appear on any
# of the lines we look for, so plain `grep` is safe (no need to render).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ZSHRC="$REPO_ROOT/dot_config/zsh/dot_zshrc.tmpl"
    ZSHENV="$REPO_ROOT/dot_zshenv"
    ZPROFILE="$REPO_ROOT/dot_config/zsh/dot_zprofile"
}

# ─── ~/.zshenv: must stay in $HOME (zsh reads it before ZDOTDIR is set) ────

@test "zshenv source file exists in the repo" {
    [ -f "$ZSHENV" ]
}

@test "zshenv sets ZDOTDIR to ~/.config/zsh" {
    # If this drops, ~/.config/zsh/.zshrc is never loaded — the user gets a
    # bare zsh with no aliases, no completions, no prompt. doctor catches
    # the missing rc; this catches the cause.
    grep -qE '^export ZDOTDIR=' "$ZSHENV"
    grep -qF '$HOME/.config/zsh' "$ZSHENV"
}

@test "zshenv exports the XDG base directories" {
    for var in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME; do
        if ! grep -qE "^export ${var}=" "$ZSHENV"; then
            echo "missing export of $var in $ZSHENV"
            return 1
        fi
    done
}

@test "zshenv points CLAUDE_CONFIG_DIR at the XDG location" {
    # Comment in zshenv: "Set in .zshenv (not .zshrc) so every zsh
    # invocation — including non-interactive scripts and editor/IDE-spawned
    # subshells — sees it." Moving it to .zshrc would silently regress that.
    grep -qE '^export CLAUDE_CONFIG_DIR=' "$ZSHENV"
    grep -qF 'XDG_CONFIG_HOME/claude' "$ZSHENV"
}

@test "zshenv sets EDITOR and VISUAL" {
    grep -qE '^export EDITOR=' "$ZSHENV"
    grep -qE '^export VISUAL=' "$ZSHENV"
}

# ─── ~/.config/zsh/.zshrc wiring ───────────────────────────────────────────

@test "zshrc template source file exists" {
    [ -f "$ZSHRC" ]
}

@test "zshrc activates mise (so per-project runtimes + JAVA_HOME work)" {
    # Without this line, `cd` into a project never switches Java/Node, and
    # JAVA_HOME stays unset. The whole mise-as-runtime-manager story breaks.
    grep -qF 'mise activate zsh' "$ZSHRC"
}

@test "zshrc initialises starship (the prompt)" {
    grep -qF 'starship init zsh' "$ZSHRC"
}

@test "zshrc initialises zoxide (smart cd)" {
    grep -qF 'zoxide init zsh' "$ZSHRC"
}

@test "zshrc wires up fzf's shell integration" {
    # fzf --zsh is fzf 0.48+'s way; an older `--bash`/install-script form
    # would mean the Ctrl-R reverse-search and Ctrl-T file-picker stop
    # working on a fresh install.
    grep -qF 'fzf --zsh' "$ZSHRC"
}

@test "zshrc sources zsh-syntax-highlighting LAST" {
    # The syntax-highlighting plugin's README is explicit: it must be the
    # last sourced file, otherwise other plugins (autosuggestions, etc.)
    # mis-render. The comment in the source file documents this; this test
    # enforces it stays the LAST `source …syntax-highlighting…` line by
    # confirming no other `source` line follows it.
    line=$(grep -n 'source.*zsh-syntax-highlighting' "$ZSHRC" | tail -1 | cut -d: -f1)
    [ -n "$line" ]
    tail -n "+$((line + 1))" "$ZSHRC" | grep -E '^[[:space:]]*source[[:space:]]' && return 1
    return 0
}

# ─── Dotfiles meta-commands that the README documents as "daily commands" ──

@test "zshrc defines the chezup function" {
    # Documented in README + AGENTS.md as one of the two everyday verbs.
    grep -qE '^chezup\(\) \{' "$ZSHRC"
}

@test "zshrc defines the chezdoctor function" {
    # Documented in README as the third everyday command.
    grep -qE '^chezdoctor\(\) \{' "$ZSHRC"
}

@test "zshrc defines the dotfiles function (control panel)" {
    grep -qE '^dotfiles\(\) \{' "$ZSHRC"
}

@test "zshrc defines the chez wrapper around chezmoi apply" {
    grep -qE '^chez\(\) \{' "$ZSHRC"
}
