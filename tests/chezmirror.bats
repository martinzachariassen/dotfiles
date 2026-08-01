#!/usr/bin/env bats
# Behavioural tests for the Brewfile-removal reconciler: chezmirror and the
# helpers it shares with chezbump (_chez_brew_removals, _chez_brew_uninstall_one).
#
# Why this exists:
#   chezmirror uninstalls Homebrew packages tracked in NO Brewfile tier. The
#   dangerous, subtle bit is computing that "untracked" set: `brew bundle
#   cleanup` honours only ONE --file, so the tiers must be concatenated and
#   piped in via --file=-. Passing several --file reads just the LAST tier and
#   would report almost the entire toolchain as untracked — one confirmed run
#   would wipe the machine. These tests pin the union, the parser, the
#   cask-vs-formula uninstall dispatch, and the no-TTY safety guard by
#   extracting the REAL functions from the template and running them against a
#   stubbed `brew`/`gum` — so a regression in the committed source fails here.
#
#   The interactive per-package loop needs a controlling terminal, so the two
#   TTY-dependent tests are inverse-gated: the safety test runs headless (CI),
#   the confirm-loop test runs only under a real/pseudo tty. Run the loop test
#   locally with:  script -q /dev/null bats tests/chezmirror.bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ZSHRC="$REPO_ROOT/src/exact_dot_config/zsh/dot_zshrc.tmpl"
    command -v bash >/dev/null 2>&1 || skip "bash not installed"

    # A fake repo whose four Brewfile tiers the helper concatenates. Distinct
    # markers per tier let us prove the UNION (all four) reaches brew's stdin.
    FAKE="$(mktemp -d)"
    mkdir -p "$FAKE/packages"
    printf 'brew "marker-core"\n' >"$FAKE/packages/Brewfile"
    printf 'cask "marker-macapps"\n' >"$FAKE/packages/Brewfile.mac-apps"
    printf 'brew "marker-personal"\n' >"$FAKE/packages/Brewfile.personal"
    printf 'brew "marker-work"\n' >"$FAKE/packages/Brewfile.work"

    # Stub bin dir (prepended to PATH) + log/queue files the stubs read/write.
    STUBS="$(mktemp -d)"
    CANNED="$STUBS/cleanup.out"     # what stub `brew bundle cleanup` prints
    ARGS_LOG="$STUBS/brew-args.log" # args passed to `brew bundle cleanup`
    STDIN_LOG="$STUBS/brew-stdin"   # what got piped into `brew bundle cleanup`
    UNINSTALL_LOG="$STUBS/uninstall.log"

    # Representative cleanup output: one cask + two formulae, then the cache-
    # pruning section newer Homebrew appends. The parser MUST stop at
    # "Would `brew cleanup`:" — otherwise every "Would remove: …/Caches/…" line
    # leaks in as a bogus "formula" removal (the bug this pins).
    cat >"$CANNED" <<'EOF'
Would uninstall casks:
orphan-app
Would uninstall formulae:
bats-core
orphan-cli
Would `brew cleanup`:
Would remove: /Users/x/Library/Caches/Homebrew/fmt--12.1.0 (282.9KB)
Would remove: /Users/x/Library/Caches/Homebrew/Cask/claude--2.1.187 (216.0MB)
EOF

    cat >"$STUBS/brew" <<EOF
#!/usr/bin/env bash
if [ "\$1" = bundle ] && [ "\$2" = cleanup ]; then
    shift 2
    printf 'cleanup %s\n' "\$*" >>"$ARGS_LOG"
    cat >"$STDIN_LOG"          # capture the piped-in union
    cat "$CANNED" 2>/dev/null  # emit the canned preview
    exit 0
fi
if [ "\$1" = uninstall ]; then
    shift
    printf '%s\n' "\$*" >>"$UNINSTALL_LOG"
    exit 0
fi
if [ "\$1" = untap ]; then
    shift
    printf 'untap %s\n' "\$*" >>"$UNINSTALL_LOG"
    exit 0
fi
exit 0
EOF

    # Real `gum confirm` (bubbletea) reads keypresses from STDIN. The stub mirrors
    # that: one answer line per confirm, consumed from stdin. This is what makes
    # the confirm-loop test able to catch the bug — if chezmirror ever feeds the
    # package list on stdin again, gum reads packages instead of these answers.
    cat >"$STUBS/gum" <<'EOF'
#!/usr/bin/env bash
[ "$1" = confirm ] || exit 0
IFS= read -r ans || ans=""
[ "$ans" = yes ]
EOF
    chmod +x "$STUBS/brew" "$STUBS/gum"
}

teardown() {
    [ -n "${FAKE:-}" ] && rm -rf "$FAKE"
    [ -n "${STUBS:-}" ] && rm -rf "$STUBS"
}

# Pull one or more function bodies out of the template, repointing the single
# `local src={{ .chezmoi.workingTree | quote }}` line at the fake repo. The
# helpers carry no template directives, so only chezmirror's src line changes.
extract() {
    local fn
    for fn in "$@"; do
        sed -n "/^${fn}() {/,/^}/p" "$ZSHRC"
    done | sed "s|^    local src={{.*}}|    local src=\"$FAKE\"|"
}

# Can this process actually open a controlling terminal? Mirrors the guard the
# function itself uses, so the TTY-gated tests agree with production behaviour.
have_tty() { { : </dev/tty; } >/dev/null 2>&1; }

run_fn() { # run_fn 'shell snippet' — under stubbed PATH + exported log paths
    run env \
        PATH="$STUBS:$PATH" \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash -c "$1"
}

# ─── _chez_brew_removals: the union + parser (the bug lived here) ────────────

@test "_chez_brew_removals parses cleanup output into <kind><TAB><name> rows" {
    run_fn "$(extract _chez_brew_removals); _chez_brew_removals '$FAKE'"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(printf 'cask\torphan-app')" ]
    [ "${lines[1]}" = "$(printf 'formula\tbats-core')" ]
    [ "${lines[2]}" = "$(printf 'formula\torphan-cli')" ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "_chez_brew_removals stops at the cache-prune section (no leaked paths)" {
    run_fn "$(extract _chez_brew_removals); _chez_brew_removals '$FAKE'"
    [ "$status" -eq 0 ]
    # The "Would `brew cleanup`:" section and its "Would remove: …/Caches/…"
    # lines must NEVER surface as removals — that's the parser bug regression.
    ! grep -q 'Would remove' <<<"$output"
    ! grep -q 'Caches/Homebrew' <<<"$output"
    ! grep -q 'brew cleanup' <<<"$output"
}

@test "_chez_brew_removals labels the untap section 'tap' without leaking its header" {
    # Modern `brew bundle cleanup` appends a "Would untap:" section (each entry a
    # tap name like "supabase/tap") after dropping a tap's last tracked formula.
    # Neither the header nor its entries may inherit the preceding "formula" kind
    # — the bug that made chezmirror `brew uninstall "Would untap:"` and a bare
    # tap name. They must surface as their own "tap" kind for `brew untap`.
    cat >"$CANNED" <<'EOF'
Would uninstall formulae:
orphan-cli
Would untap:
acme/formulae
EOF
    run_fn "$(extract _chez_brew_removals); _chez_brew_removals '$FAKE'"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(printf 'formula\torphan-cli')" ]
    [ "${lines[1]}" = "$(printf 'tap\tacme/formulae')" ]
    [ "${#lines[@]}" -eq 2 ]
    ! grep -q 'Would untap' <<<"$output" # the header itself must never leak
}

@test "_chez_brew_removals feeds the UNION of all four tiers to brew (bug regression)" {
    run_fn "$(extract _chez_brew_removals); _chez_brew_removals '$FAKE'"
    [ "$status" -eq 0 ]
    # Every tier's marker must reach brew's stdin — not just the last file's.
    for m in marker-core marker-macapps marker-personal marker-work; do
        grep -qF "$m" "$STDIN_LOG" || {
            echo "missing $m from brew stdin:"
            cat "$STDIN_LOG"
            return 1
        }
    done
}

@test "_chez_brew_removals sweeps in a newly-added tier (apple-dev glob regression)" {
    # The original bug: the helper hardcoded four tier filenames and silently
    # ignored a fifth one added later (Brewfile.apple-dev), so every package
    # tracked ONLY there read as untracked and got queued for uninstall. The tier
    # set must be the `Brewfile.*` glob, so ANY new tier is honoured with no code
    # change. Drop a fifth tier the hardcoded list never knew about and prove its
    # contents reach brew's stdin.
    printf 'brew "marker-appledev"\n' >"$FAKE/packages/Brewfile.apple-dev"
    run_fn "$(extract _chez_brew_removals); _chez_brew_removals '$FAKE'"
    [ "$status" -eq 0 ]
    grep -qF marker-appledev "$STDIN_LOG" || {
        echo "the apple-dev tier never reached brew stdin (glob regressed):"
        cat "$STDIN_LOG"
        return 1
    }
}

@test "_chez_brew_removals passes a single --file=- (never multiple --file)" {
    run_fn "$(extract _chez_brew_removals); _chez_brew_removals '$FAKE'"
    [ "$status" -eq 0 ]
    [ "$(cat "$ARGS_LOG")" = "cleanup --file=-" ]
    # Belt-and-braces: exactly one --file token — the whole point of the fix.
    [ "$(grep -o -- '--file' "$ARGS_LOG" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "_chez_brew_removals yields nothing when brew reports no removals" {
    : >"$CANNED" # brew bundle cleanup prints nothing
    run_fn "$(extract _chez_brew_removals); _chez_brew_removals '$FAKE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── _chez_brew_uninstall_one: cask-vs-formula dispatch ─────────────────────

@test "_chez_brew_uninstall_one routes casks through --cask, formulae plain" {
    run_fn "$(extract _chez_brew_uninstall_one)
        _chez_brew_uninstall_one cask my-app
        _chez_brew_uninstall_one formula my-cli"
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "$UNINSTALL_LOG")" = "--cask my-app" ]
    [ "$(sed -n 2p "$UNINSTALL_LOG")" = "my-cli" ]
}

@test "_chez_brew_uninstall_one routes taps through untap (never uninstall)" {
    run_fn "$(extract _chez_brew_uninstall_one)
        _chez_brew_uninstall_one tap acme/formulae"
    [ "$status" -eq 0 ]
    [ "$(cat "$UNINSTALL_LOG")" = "untap acme/formulae" ]
}

# ─── chezmirror: end-to-end behaviour ───────────────────────────────────────

@test "chezmirror reports nothing to remove when every package is tracked" {
    : >"$CANNED" # nothing untracked
    run_fn "$(extract chezmirror _chez_brew_removals _chez_brew_uninstall_one); chezmirror"
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to remove"* ]]
    [ ! -s "$UNINSTALL_LOG" ] # never uninstalled anything
}

@test "chezmirror refuses to uninstall without a controlling terminal (safety)" {
    have_tty && skip "has a controlling tty; see the confirm-loop test instead"
    run_fn "$(extract chezmirror _chez_brew_removals _chez_brew_uninstall_one); chezmirror"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No TTY"* ]]
    # It previewed the untracked set but uninstalled NOTHING.
    [[ "$output" == *"orphan-app"* ]]
    [ ! -s "$UNINSTALL_LOG" ]
}

@test "chezmirror uninstalls only the confirmed packages, one at a time" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # Answers arrive on STDIN (as real gum reads them): confirm the cask, decline
    # bats-core, confirm the other formula. This is the bug's regression test —
    # if chezmirror feeds the package list on stdin again, gum reads packages
    # instead of these answers and the loop miscounts / drains early.
    run env \
        PATH="$STUBS:$PATH" \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash -c "$(extract chezmirror _chez_brew_removals _chez_brew_uninstall_one); chezmirror" <<<$'yes\nno\nyes'
    [ "$status" -eq 0 ]
    # orphan-app (cask, routed via --cask) and orphan-cli removed; bats-core kept.
    [ "$(sed -n 1p "$UNINSTALL_LOG")" = "--cask orphan-app" ]
    [ "$(sed -n 2p "$UNINSTALL_LOG")" = "orphan-cli" ]
    [ "$(wc -l <"$UNINSTALL_LOG" | tr -d ' ')" -eq 2 ]
    ! grep -qx "bats-core" "$UNINSTALL_LOG"
    [[ "$output" == *"removed 2 · kept 1"* ]]
}

# ─── chezmirror accept-all mode (--all / --yes / YES=1) ─────────────────────

@test "chezmirror --help prints usage and removes nothing" {
    run_fn "$(extract chezmirror _chez_brew_removals _chez_brew_uninstall_one); chezmirror --help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: chezmirror"* ]]
    [[ "$output" == *"--all"* ]]
    [ ! -s "$UNINSTALL_LOG" ] # help path never touches brew
}

@test "chezmirror rejects an unknown option (exit 2, no uninstall)" {
    run_fn "$(extract chezmirror _chez_brew_removals _chez_brew_uninstall_one); chezmirror --bogus"
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option"* ]]
    [ ! -s "$UNINSTALL_LOG" ]
}

@test "chezmirror --all uninstalls the whole set after ONE confirmation" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # A single 'yes' on stdin gates the whole batch; the per-package loop then
    # runs unattended (no further prompts), so exactly one gum answer is consumed.
    run env \
        PATH="$STUBS:$PATH" \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash -c "$(extract chezmirror _chez_brew_removals _chez_brew_uninstall_one); chezmirror --all" <<<$'yes'
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "$UNINSTALL_LOG")" = "--cask orphan-app" ]
    [ "$(sed -n 2p "$UNINSTALL_LOG")" = "bats-core" ]
    [ "$(sed -n 3p "$UNINSTALL_LOG")" = "orphan-cli" ]
    [ "$(wc -l <"$UNINSTALL_LOG" | tr -d ' ')" -eq 3 ]
    [[ "$output" == *"removed 3 · kept 0"* ]]
}

@test "chezmirror --all aborts cleanly when the bulk confirm is declined" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    run env \
        PATH="$STUBS:$PATH" \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash -c "$(extract chezmirror _chez_brew_removals _chez_brew_uninstall_one); chezmirror --all" <<<$'no'
    [ "$status" -eq 0 ]
    [[ "$output" == *"aborted"* ]]
    [ ! -s "$UNINSTALL_LOG" ]
}

@test "YES=1 chezmirror accepts all with no prompt at all" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # No stdin fed: YES=1 must not read any answer (bulk confirm skipped, per-item
    # prompts skipped). A stray read would hang; </dev/null proves it never reads.
    run env \
        PATH="$STUBS:$PATH" YES=1 \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash -c "$(extract chezmirror _chez_brew_removals _chez_brew_uninstall_one); chezmirror" </dev/null
    [ "$status" -eq 0 ]
    [ "$(wc -l <"$UNINSTALL_LOG" | tr -d ' ')" -eq 3 ]
    [[ "$output" == *"removed 3 · kept 0"* ]]
}

@test "chezmirror removes an interdependent set despite deps-first order (retry passes)" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # `brew bundle cleanup` lists a dependency BEFORE its dependent, so a one-shot
    # uninstall of that order fails ("still required by …") on the dep — the exact
    # symptom chezmirror showed. Model it: `libpng` refuses until `cairo` is gone,
    # and CANNED lists libpng first. The retry-in-passes loop must still clear both.
    cat >"$CANNED" <<'EOF'
Would uninstall formulae:
libpng
cairo
EOF
    # Stateful stub: uninstalling libpng fails while cairo is still installed.
    cat >"$STUBS/brew" <<EOF
#!/usr/bin/env bash
if [ "\$1" = bundle ] && [ "\$2" = cleanup ]; then
    cat >/dev/null            # drain the piped-in union
    cat "$CANNED" 2>/dev/null # emit the canned preview
    exit 0
fi
if [ "\$1" = uninstall ]; then
    shift
    if [ "\$*" = libpng ] && ! grep -qx cairo "$UNINSTALL_LOG" 2>/dev/null; then
        echo "Error: Refusing to uninstall libpng because it is required by cairo" >&2
        exit 1
    fi
    printf '%s\n' "\$*" >>"$UNINSTALL_LOG"
    exit 0
fi
exit 0
EOF
    chmod +x "$STUBS/brew"
    run env \
        PATH="$STUBS:$PATH" YES=1 \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash -c "$(extract chezmirror _chez_brew_removals _chez_brew_uninstall_one); chezmirror" </dev/null
    [ "$status" -eq 0 ]
    # Both removed, cairo first (it unblocked libpng), nothing left stuck. NOTE:
    # `[[ … ]]` does NOT fail a bats test as a non-final line (bash set -e skips
    # it), so every assertion here is a set -e-guarding simple command — `[ … ]`
    # or `grep`. A no-op `[[ … ]]` would let a regression pass silently.
    [ "$(sed -n 1p "$UNINSTALL_LOG")" = "cairo" ]
    [ "$(sed -n 2p "$UNINSTALL_LOG")" = "libpng" ]
    [ "$(wc -l <"$UNINSTALL_LOG" | tr -d ' ')" -eq 2 ]
    grep -qF "removed 2 · kept 0" <<<"$output"
    [ "$(grep -cF "still installed" <<<"$output")" -eq 0 ] # nothing left stuck
}

@test "chezmirror reports a package it can never remove instead of erroring out" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # `libpng` can never be uninstalled (something outside the Brewfiles still needs
    # it); `zlib` removes fine. The retry loop must remove zlib, give up on libpng
    # after a no-progress pass (no infinite loop), report it once under "still
    # installed", count it as neither removed nor kept, and still exit 0.
    cat >"$CANNED" <<'EOF'
Would uninstall formulae:
libpng
zlib
EOF
    cat >"$STUBS/brew" <<EOF
#!/usr/bin/env bash
if [ "\$1" = bundle ] && [ "\$2" = cleanup ]; then
    cat >/dev/null
    cat "$CANNED" 2>/dev/null
    exit 0
fi
if [ "\$1" = uninstall ]; then
    shift
    [ "\$*" = libpng ] && {
        echo "Error: Refusing to uninstall libpng because it is required" >&2
        exit 1
    }
    printf '%s\n' "\$*" >>"$UNINSTALL_LOG"
    exit 0
fi
exit 0
EOF
    chmod +x "$STUBS/brew"
    run env \
        PATH="$STUBS:$PATH" YES=1 \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash -c "$(extract chezmirror _chez_brew_removals _chez_brew_uninstall_one); chezmirror" </dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$UNINSTALL_LOG")" = "zlib" ]     # only zlib actually left
    # Guard with `grep`, not `[[ … ]]` — a non-final `[[ … ]]` never fails a bats
    # test (set -e skips it), so it would rubber-stamp the old "! failed" wording.
    grep -qF "still installed" <<<"$output"     # the stuck pkg is reported cleanly
    grep -qF "libpng" <<<"$output"              # …by name
    grep -qF "removed 1 · kept 0" <<<"$output"  # stuck ≠ kept (kept is declined only)
}

@test "chezmirror untaps an untracked tap end-to-end (Would untap regression)" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # A tap-only preview: pre-fix this fed `brew uninstall "Would untap:"` and a
    # bare tap name (both errored). Now it must route through `brew untap`.
    cat >"$CANNED" <<'EOF'
Would untap:
acme/formulae
EOF
    run env \
        PATH="$STUBS:$PATH" YES=1 \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash -c "$(extract chezmirror _chez_brew_removals _chez_brew_uninstall_one); chezmirror" </dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$UNINSTALL_LOG")" = "untap acme/formulae" ]
    [[ "$output" == *"removed 1 · kept 0"* ]]
}
