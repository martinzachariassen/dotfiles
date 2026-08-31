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
    load '../core/testing/helper'
    ZSHENV="$REPO_ROOT/src/dot_zshenv"
    ZPROFILE="$REPO_ROOT/src/dot_config/zsh/dot_zprofile"
    # The alias assertions below are driven by the verb table rather than by a
    # list repeated here, which is the whole point of having the table.
    # shellcheck source=../core/verbs.sh
    . "$REPO_ROOT/core/verbs.sh"
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

# ─── ~/.config/zsh/.zprofile: what GUI-launched apps actually get ──────────
#
# A macOS app started from the Dock inherits launchd's PATH, and VS Code widens
# it by resolving a *non-interactive login* zsh — .zshenv + .zprofile, never
# .zshrc. So `mise activate` (interactive-only, by design) cannot be what puts a
# runtime in an editor's PATH: that is this file's job, via the shims. When it
# regressed, VS Code's Kotlin LSP failed with `Cannot run program "mvn"`.
#
# These run a real login-shell PATH build against a fake shims dir, because the
# regression that motivated them (a line that grep would still match) was an
# ordering/guard bug, and CI has no mise to test against.

# Source $ZPROFILE in a pristine zsh with $1 as XDG_DATA_HOME, then run $2.
_zprofile_path() {
    zsh -f -c "
        typeset -U path
        HOME='$BATS_TEST_TMPDIR/home'
        XDG_DATA_HOME='$1'
        PATH=/usr/bin:/bin
        source '$ZPROFILE'
        $2
    "
}

@test "a login shell gets mise's shims on PATH (no .zshrc involved)" {
    mkdir -p "$BATS_TEST_TMPDIR/data/mise/shims"
    printf '#!/bin/sh\n' >"$BATS_TEST_TMPDIR/data/mise/shims/mvn"
    chmod +x "$BATS_TEST_TMPDIR/data/mise/shims/mvn"

    run _zprofile_path "$BATS_TEST_TMPDIR/data" 'command -v mvn'
    [ "$status" -eq 0 ]
    [ "$output" = "$BATS_TEST_TMPDIR/data/mise/shims/mvn" ]
}

@test "shims outrank /usr/bin, so mise's JDK beats the macOS java stub" {
    # /usr/bin/java exists on every Mac and only prints "no Java runtime".
    # Appending the shims instead of prepending would hand editors that stub.
    mkdir -p "$BATS_TEST_TMPDIR/data/mise/shims"
    run _zprofile_path "$BATS_TEST_TMPDIR/data" 'print -rl -- $path'
    [ "$status" -eq 0 ]
    shims_at="$(grep -nxF "$BATS_TEST_TMPDIR/data/mise/shims" <<<"$output" | cut -d: -f1)"
    usr_at="$(grep -nxF /usr/bin <<<"$output" | cut -d: -f1)"
    [ -n "$shims_at" ]
    [ "$shims_at" -lt "$usr_at" ]
}

@test "no shims dir yet (pre-first-install) leaves PATH clean" {
    # An unguarded prepend puts a non-existent dir on every login shell's PATH.
    run _zprofile_path "$BATS_TEST_TMPDIR/absent" 'print -rl -- $path'
    [ "$status" -eq 0 ]
    no_match_in "$output" 'mise/shims'
}

@test "zprofile keeps Homebrew ahead of /usr/bin" {
    # The shims prepend sits next to this; a bad edit could reorder it.
    grep -qF '/opt/homebrew/bin' "$ZPROFILE"
    grep -qF '$HOME/.local/bin' "$ZPROFILE"
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

# ─── The chez dispatcher ────────────────────────────────────────────────────
# Every verb used to be its own zsh function, each asserted here by name. They
# are one dispatcher now, so what this file pins is the wiring: that `chez`
# exists, that it self-heals, that `cd` stays in the shell, and that the aliases
# and the verb table agree. Behaviour lives in tests/chez.bats.

@test "zshrc defines the chez dispatcher" {
    grep -qE '^chez\(\) \{' "$ZSHRC"
}

# The dispatcher must route through _chez_run so a moved or renamed helper
# self-heals instead of stranding the very command you would fix it with.
@test "zshrc defines the _chez_run self-heal wrapper" {
    grep -qE '^_chez_run\(\) \{' "$ZSHRC"
    # It must fall back to re-applying when the baked script path is missing.
    sed -n '/^_chez_run() {/,/^}/p' "$ZSHRC" | grep -qF 'chezmoi apply'
}

@test "chez routes through _chez_run, not a bare path into the repo" {
    body="$(sed -n '/^chez() {/,/^}/p' "$ZSHRC")"
    grep -qF '_chez_run core/chez.sh "$@"' <<<"$body"
    # A bare `bash "$src/..."` would skip the self-heal entirely.
    no_match 'bash "\$src/' <<<"$body"
}

# `chez cd` has to change THIS shell's directory, so it cannot be delegated to
# a subprocess — which is the whole reason chez is a function and not a script.
@test "chez handles cd itself, before anything is delegated" {
    body="$(sed -n '/^chez() {/,/^}/p' "$ZSHRC")"
    grep -qE '\bcd "\$src"' <<<"$body"
    # The cd branch must come first; delegating it would silently no-op.
    [ "$(grep -n 'cd "$src"' <<<"$body" | head -1 | cut -d: -f1)" \
        -lt "$(grep -n '_chez_run' <<<"$body" | head -1 | cut -d: -f1)" ]
}

# Module gating is a render-time decision passed in, not a `chezmoi data` call
# on every help. If this stops being exported, help and dispatch fall back to a
# ~200 ms subprocess per invocation and nothing fails loudly enough to notice.
@test "chez exports the module set it was rendered with" {
    sed -n '/^chez() {/,/^}/p' "$ZSHRC" | grep -qF 'local -x CHEZ_MODULES='
}

@test "zshrc offers completion for chez, fed by the dispatcher itself" {
    grep -qE '^_chez\(\) \{' "$ZSHRC"
    grep -qF 'compdef _chez chez' "$ZSHRC"
    # Fed from `chez --verbs` rather than a hand-written list, so a new verb
    # completes without touching this file.
    sed -n '/^_chez() {/,/^}/p' "$ZSHRC" | grep -qF -- '--verbs'
}

# compdef is a compinit builtin: registering before compinit runs is a silent
# no-op, and completion for chez simply never appears.
@test "compdef for chez comes after compinit" {
    [ "$(grep -n 'compinit -' "$ZSHRC" | head -1 | cut -d: -f1)" \
        -lt "$(grep -n 'compdef _chez chez' "$ZSHRC" | cut -d: -f1)" ]
}

# The aliases are retired. `chezup`, `chezdoctor`, `dotfiles`, `macos-defaults`
# and the rest existed through the transition and are gone; there is one
# spelling of every verb. A stale alias is worse than a missing one — it keeps
# two names alive in muscle memory and in half the docs, which is the drift the
# registry exists to end.
@test "no retired name survives as an alias" {
    local bad=() v retired
    while IFS= read -r v; do
        retired="$(verbs_retired_name "$v")"
        [ -n "$retired" ] || continue
        grep -qE "^alias ${retired}=" "$ZSHRC" && bad+=("$retired")
    done < <(verbs_all)
    [ "${#bad[@]}" -eq 0 ] || printf 'retired alias still defined: %s\n' "${bad[@]}" >&2
    [ "${#bad[@]}" -eq 0 ]
}

@test "the zshrc defines no chez-prefixed alias at all" {
    # Broader than the list above: it also catches a new `chezfoo` growing back,
    # which would reintroduce the second spelling this stage removed.
    local strays
    strays="$(grep -oE "^alias chez[a-z]+=" "$ZSHRC" || true)"
    [ -z "$strays" ] || {
        printf 'a chez-prefixed alias reappeared: %s\n' "$strays" >&2
        return 1
    }
}

# Every verb that touches Homebrew is a script now, so no copy of the removal
# logic may remain in the template.
@test "the template keeps no copy of the package-removal logic" {
    no_match 'brew bundle cleanup' "$ZSHRC"
    no_match '_chez_brew_removals\(\)' "$ZSHRC"
}

# The per-verb wrappers are gone; nothing may quietly grow one back, because a
# hand-written wrapper bypasses the table that help and completion read.
@test "no per-verb wrapper survives in the template" {
    local strays
    strays="$(grep -oE '^chez[a-z]+\(\) \{' "$ZSHRC" || true)"
    [ -z "$strays" ] || {
        printf 'per-verb wrapper still in the zshrc: %s\n' "$strays" >&2
        return 1
    }
}

# chez apply reports package drift and points at chez mirror; it must never
# uninstall. Asserted against the script now — the template only wraps it.
@test "chez apply surfaces Brewfile drift but never auto-uninstalls" {
    APPLY="$REPO_ROOT/features/converge/apply.sh"
    grep -qF 'brew_removals' "$APPLY"
    grep -qF 'reconcile (uninstall): chez mirror' "$APPLY"
    no_match 'brew (bundle cleanup|uninstall|untap)' "$APPLY"
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
    for later in 'compinit -u -d' '_zcache mise' '_zcache starship' '_zcache fzf'; do
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
    grep -qE '^[[:space:]]*compinit -u -d "\$ZSH_COMPDUMP"$' "$ZSHRC"
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
