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

# Negative assertions must go through these. A bare `! grep …` in the middle of
# a test body is exempt from set -e (POSIX: "the return value is being inverted
# with !"), so bats never sees it fail — the assertion silently passes no matter
# what the file contains. Verified: mutating the source under a bare `! grep`
# left the test green.
#
# no_match <extended-regex> <file…>
no_match() {
    if grep -qE "$@"; then
        echo "unexpected match for: $1"
        return 1
    fi
}

# no_match_in <text> <extended-regex>
no_match_in() {
    if grep -qE "$2" <<<"$1"; then
        echo "unexpected match for: $2"
        return 1
    fi
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
    no_match_in "$body" 'brew bundle cleanup --force'

    # `brew bundle cleanup` honours only ONE --file; tiers must arrive on
    # stdin (--file=-) or only the last tier would be read.
    grep -qE '^_chez_brew_removals\(\) \{' "$ZSHRC"
    helper="$(sed -n '/^_chez_brew_removals() {/,/^}/p' "$ZSHRC")"
    grep -qF 'brew bundle cleanup --file=-' <<<"$helper"
    no_match 'brew bundle cleanup[^|]*--file=[^-]' "$ZSHRC"
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

# ─── Startup cost ──────────────────────────────────────────────────────────
# Everything here is a performance property, so nothing surfaces a regression:
# the shell keeps working, it just gets slower. These pin the structure that
# makes it fast, not a wall-clock number (which would be flaky in CI).

# Line number of the first match of $1, or empty.
_line_of() { grep -nF -m1 "$1" "$ZSHRC" | cut -d: -f1; }

@test "the Zellij auto-attach runs before compinit and the tool inits" {
    # A Ghostty tab that attaches hands the terminal to Zellij, and the shell
    # inside the pane sources this file again — so every line above the attach
    # is paid twice per tab. It used to sit at the very bottom.
    attach="$(_line_of 'zellij attach -c "$_ZJ_SESSION"')"
    [ -n "$attach" ]
    for later in 'compinit -d' '_zcache mise' '_zcache starship' '_zcache fzf'; do
        at="$(_line_of "$later")"
        [ -n "$at" ] || { echo "not found: $later"; return 1; }
        [ "$attach" -lt "$at" ] || {
            echo "'$later' (line $at) runs before the attach (line $attach)"
            return 1
        }
    done
}

@test "detaching from Zellij falls through to the rest of the shell config" {
    # The attach must be a plain call: no exec (the tab would die on detach) and
    # no return/exit after it (the detached shell would have no prompt, no
    # aliases and no highlighting).
    block="$(sed -n '/zellij attach -c "\$_ZJ_SESSION"/,/^fi$/p' "$ZSHRC")"
    # POSIX classes, not \s / \b: BSD grep on macOS doesn't understand those and
    # would quietly match nothing.
    no_match '^[[:space:]]*exec zellij' "$ZSHRC"
    no_match_in "$block" '^[[:space:]]*(return|exit)([[:space:]]|$)'
    # And the tail of the file must still be reachable.
    attach="$(_line_of 'zellij attach -c "$_ZJ_SESSION"')"
    hl="$(_line_of 'zsh-syntax-highlighting.zsh')"
    [ "$attach" -lt "$hl" ]
}

@test "_zj_prune stays synchronous in the attach path" {
    # _zj_pick_session counts *exited* sessions as taken, so the prune has to
    # have finished before it runs. Backgrounding it (a tempting ~25ms saving)
    # hands every new tab a "<project>-2" name instead.
    grep -qE '^[[:space:]]*_zj_prune$' "$ZSHRC"
    no_match '_zj_prune[[:space:]]*&' "$ZSHRC"
}

@test "every tool init is memoised through _zcache" {
    # A bare eval "$(tool init)" is a fork plus a parse on every interactive
    # shell; five of them measured ~44ms. _zcache writes the generated script
    # once and byte-compiles it.
    grep -qE '^_zcache\(\) \{' "$ZSHRC"
    for tool in mise fzf zoxide starship carapace; do
        grep -qE "_zcache ${tool} ${tool} " "$ZSHRC" || {
            echo "$tool is not routed through _zcache"
            return 1
        }
    done
    # No stragglers left on the slow path.
    no_match 'eval "\$\((mise|fzf|zoxide|starship|carapace) ' "$ZSHRC"
}

@test "each _zcache line passes a command line that really prints an init script" {
    # _zcache's argv is <cache-name> <cmd…>, where <cmd> doubles as the binary
    # it probes — so the tool name appears exactly twice, not three times.
    # `_zcache mise mise mise activate zsh` ran `mise mise activate zsh`, which
    # prints nothing, and the old _zcache swallowed the error: mise never
    # activated, so GUI-launched editors lost every mise-managed runtime from
    # PATH (no mvn/java) while interactive shells that predated the change
    # looked fine. Grepping for the string can't see this — we run it.
    while read -r line; do
        # Word-splitting is the point: rebuild _zcache's argv from the source.
        # shellcheck disable=SC2086
        set -- $line
        shift 2 # drop "_zcache" and the cache name; $@ is what _zcache execs
        command -v "$1" >/dev/null 2>&1 || continue # tool absent in this env
        out="$("$@" </dev/null 2>/dev/null)" || {
            echo "\`$*\` exited non-zero; _zcache would cache nothing"
            return 1
        }
        [ -n "$out" ] || {
            echo "\`$*\` printed no init script; _zcache would cache a no-op"
            return 1
        }
    done < <(grep -E '^[[:space:]]*_zcache [a-z]' "$ZSHRC" | sed 's/^[[:space:]]*//')
}

@test "_zcache never caches an empty init and never sources a stale temp file" {
    # The empty-output guard is what turns a broken argv into a visible error
    # instead of a permanently disabled integration ([ -s ] is true at 1 byte,
    # so "not empty" alone was not enough to notice carapace printing "\n").
    body="$(sed -n '/^_zcache() {/,/^}/p' "$ZSHRC")"
    grep -qF '&& [[ -s $tmp ]]' <<<"$body"
    # Failures must be reported, not routed to /dev/null and forgotten.
    grep -qF 'could not generate' <<<"$body"
    # And a failed regeneration must not clobber the last known-good init.
    no_match_in "$body" 'rm -f "\$f"'
}

@test "compinit is not unconditionally -C" {
    # -C skips the fpath re-scan, so a newly brew-installed completion stays
    # invisible until the dump is rebuilt. With only `compinit -C` in the file
    # that never happens on its own.
    grep -qF 'compinit -C -d' "$ZSHRC"
    grep -qE '^[[:space:]]*compinit -d "\$ZSH_COMPDUMP"$' "$ZSHRC"
    # Version-keyed, or a zsh upgrade silently breaks completion.
    grep -qF 'zcompdump-$ZSH_VERSION' "$ZSHRC"
}

@test "history is safe for concurrent panes and doesn't self-truncate" {
    # SHARE_HISTORY + many Zellij panes = interleaved appends without locking.
    grep -qE '^setopt HIST_FCNTL_LOCK$' "$ZSHRC"
    grep -qE '^setopt SHARE_HISTORY$' "$ZSHRC"
    # Dedup/expiry cull the in-memory list, so it needs headroom over SAVEHIST.
    histsize="$(grep -E '^HISTSIZE=' "$ZSHRC" | tail -1 | cut -d= -f2)"
    savehist="$(grep -E '^SAVEHIST=' "$ZSHRC" | tail -1 | cut -d= -f2)"
    [ "$histsize" -gt "$savehist" ]
}

@test "the zprof guard is paired and cannot leave \$? nonzero" {
    # zprof must be the last statement to profile everything, and a bare
    # `[[ ... ]] && zprof` there would exit 1 whenever ZSH_PROFILE is unset —
    # starship then flags an error on the very first prompt.
    grep -qF 'zmodload zsh/zprof' "$ZSHRC"
    grep -qF '} || true' "$ZSHRC"
    tail -1 "$ZSHRC" | grep -qF 'zprof'
}
