#!/usr/bin/env bats
# Pin the critical tool activations and env-var wiring in the managed shell.
#
# `render-check.sh`'s `zsh -n` catches parse errors, not silent deletes — if
# `eval "$(mise activate zsh)"` gets removed, the file still parses but
# per-project runtime switching and JAVA_HOME silently break. Same risk for
# starship, zoxide, fzf, and the XDG/CLAUDE_CONFIG_DIR exports in zshenv.
#
# We grep the templates directly — none of the lines we look for carry
# Go-template directives, so plain grep is safe without rendering.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"
    ZSHENV="$REPO_ROOT/src/dot_zshenv"
    ZPROFILE="$REPO_ROOT/src/dot_config/zsh/dot_zprofile"
}

# ─── ~/.zshenv: must stay in $HOME (zsh reads it before ZDOTDIR is set) ────

@test "zshenv source file exists in the repo" {
    [ -f "$ZSHENV" ]
}

@test "zshenv sets ZDOTDIR to ~/.config/zsh" {
    # If this drops, ~/.config/zsh/.zshrc is never loaded — bare zsh, no prompt.
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
    # Must live in .zshenv, not .zshrc, so non-interactive/IDE subshells see it.
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
    grep -qF 'mise activate zsh' "$ZSHRC"
}

@test "zshrc initialises starship (the prompt)" {
    grep -qF 'starship init zsh' "$ZSHRC"
}

@test "zshrc initialises zoxide (smart cd)" {
    grep -qF 'zoxide init zsh' "$ZSHRC"
}

@test "zshrc wires up fzf's shell integration" {
    # fzf --zsh (0.48+); an older form would drop Ctrl-R/Ctrl-T on a fresh install.
    grep -qF 'fzf --zsh' "$ZSHRC"
}

@test "zshrc sources zsh-syntax-highlighting LAST" {
    # Its README requires this — sourced earlier, other plugins render wrong.
    line=$(grep -n 'source.*zsh-syntax-highlighting' "$ZSHRC" | tail -1 | cut -d: -f1)
    [ -n "$line" ]
    tail -n "+$((line + 1))" "$ZSHRC" | grep -E '^[[:space:]]*source[[:space:]]' && return 1
    return 0
}

# ─── Dotfiles meta-commands that the README documents as "daily commands" ──

@test "zshrc defines the chezup function" {
    grep -qE '^chezup\(\) \{' "$ZSHRC"
}

@test "zshrc defines the chezdoctor function" {
    grep -qE '^chezdoctor\(\) \{' "$ZSHRC"
}

# Wrappers must route through _chez_run so a moved/renamed helper self-heals
# instead of stranding the very command you'd fix it with.
@test "zshrc defines the _chez_run self-heal wrapper" {
    grep -qE '^_chez_run\(\) \{' "$ZSHRC"
    # It must fall back to re-applying when the baked script path is missing.
    sed -n '/^_chez_run() {/,/^}/p' "$ZSHRC" | grep -qF 'chezmoi apply'
}

@test "chezup and chezdoctor route through _chez_run (no stale bare-path calls)" {
    sed -n '/^chezup() {/,/^}/p' "$ZSHRC" | grep -qF '_chez_run scripts/bin/chezup.sh'
    sed -n '/^chezdoctor() {/,/^}/p' "$ZSHRC" | grep -qF '_chez_run scripts/bin/doctor.sh'
}

@test "zshrc defines the dotfiles function (control panel)" {
    grep -qE '^dotfiles\(\) \{' "$ZSHRC"
}

@test "zshrc defines the chez wrapper around chezmoi apply" {
    grep -qE '^chez\(\) \{' "$ZSHRC"
}

# chezhelp's listing must stay in sync with the actual verbs.
@test "zshrc defines chezhelp and it lists every verb" {
    grep -qE '^chezhelp\(\) \{' "$ZSHRC"
    body="$(sed -n '/^chezhelp() {/,/^}/p' "$ZSHRC")"
    for verb in chezup chezdoctor chezreset chezreinit chez chezdiff chezbump chezaudit chezmirror chezsync chezclean dotfiles; do
        grep -qE "^ +${verb} " <<<"$body" || {
            echo "chezhelp is missing an entry for: ${verb}"
            return 1
        }
    done
}

# Wiring only — the behaviour (union, parser, cask/formula dispatch, no-TTY
# safety) is exercised end-to-end in tests/chezmirror.bats against a stubbed brew.
@test "zshrc defines the chezmirror function (Brewfile removal reconcile)" {
    grep -qE '^chezmirror\(\) \{' "$ZSHRC"
    body="$(sed -n '/^chezmirror() {/,/^}/p' "$ZSHRC")"
    # Confirms per package (individually gated) — never a bulk cleanup --force.
    grep -qF '_chez_brew_removals' <<<"$body"
    grep -qF '_chez_brew_uninstall_one' <<<"$body"
    grep -qF 'gum confirm' <<<"$body"
    ! grep -qF 'brew bundle cleanup --force' <<<"$body"

    # `brew bundle cleanup` honours only ONE --file; tiers must arrive on
    # stdin (--file=-) or only the last tier would be read.
    grep -qE '^_chez_brew_removals\(\) \{' "$ZSHRC"
    helper="$(sed -n '/^_chez_brew_removals() {/,/^}/p' "$ZSHRC")"
    grep -qF 'brew bundle cleanup --file=-' <<<"$helper"
    ! grep -qE 'brew bundle cleanup[^|]*--file=[^-]' "$ZSHRC"
}

# Wiring only — behaviour is exercised end-to-end in tests/chezclean.bats.
@test "zshrc defines the chezclean function routed through _chez_run" {
    grep -qE '^chezclean\(\) \{' "$ZSHRC"
    sed -n '/^chezclean() {/,/^}/p' "$ZSHRC" | grep -qF '_chez_run scripts/bin/clean.sh'
}

# chezsync must compose chezup (install) + chezmirror (removal), never
# re-implement either. Behaviour is exercised in tests/chezsync.bats.
@test "zshrc defines chezsync composing chezup then chezmirror" {
    grep -qE '^chezsync\(\) \{' "$ZSHRC"
    body="$(sed -n '/^chezsync() {/,/^}/p' "$ZSHRC")"
    grep -qF 'chezup' <<<"$body"
    grep -qF 'chezmirror' <<<"$body"
}

@test "chez surfaces Brewfile drift but never auto-uninstalls" {
    grep -qE '^_chez_brew_untracked\(\) \{' "$ZSHRC"
    grep -qF 'reconcile (uninstall): chezmirror' "$ZSHRC"
    ! sed -n '/^chez() {/,/^}/p' "$ZSHRC" | grep -qF 'brew bundle cleanup'
}
