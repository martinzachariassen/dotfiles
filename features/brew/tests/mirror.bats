#!/usr/bin/env bats
# Tests for chez mirror and the helpers it shares with chez bump
# (brew_removals, brew_uninstall_one) — the reconciler that
# uninstalls Homebrew packages tracked in NO Brewfile tier.
#
# The dangerous bit: `brew bundle cleanup` honours only ONE --file, so the
# tiers must be concatenated and piped via --file=-. Passing several --file
# reads just the LAST tier and would report almost the whole toolchain as
# untracked — one confirmed run would wipe the machine. These tests extract
# the REAL functions from the template and run them against a stubbed
# brew/gum, so a regression in the committed source fails here.
#
# The tier set is the ACTIVE one (core + enabled modules), resolved by the real
# features/brew/lib/tiers.sh against a stubbed `chezmoi data` — not every
# `Brewfile.*` that exists. Too FEW tiers offers the toolchain for uninstall;
# too MANY (the old glob) silently keeps packages this machine has dropped.
#
# The interactive per-package loop needs a controlling terminal; the two
# TTY-dependent tests are inverse-gated (safety runs headless in CI, the
# confirm-loop test needs a real/pseudo tty). Run it locally with:
#   script -q /dev/null bats features/brew/tests/mirror.bats

setup() {
    load '../../../core/testing/helper'
    command -v bash >/dev/null 2>&1 || skip "bash not installed"

    command -v jq >/dev/null 2>&1 || skip "jq not installed (brew_active_files needs it)"

    # Fake repo with the Brewfile tiers, each with a distinct marker, so we can
    # prove exactly which ones reach brew's stdin. It carries the REAL resolver
    # lib, so these tests exercise the committed tiers.sh, not a mock of it.
    FAKE="$(mktemp -d)"
    mkdir -p "$FAKE/features/brew/lib" "$FAKE/core"
    cp "$REPO_ROOT/features/brew/lib/tiers.sh" "$FAKE/features/brew/lib/tiers.sh"
    # tiers.sh refuses to load without it, on purpose: without core/paths.sh it
    # cannot find the machine-local overlay, and every package adopted there
    # would land in exactly the removal set these tests are about.
    cp "$REPO_ROOT/core/paths.sh" "$FAKE/core/paths.sh"
    printf 'brew "marker-core"\n' >"$FAKE/features/brew/Brewfile"
    printf 'cask "marker-macapps"\n' >"$FAKE/features/brew/Brewfile.mac-apps"

    # Stub bin dir (prepended to PATH) + log/queue files the stubs read/write.
    STUBS="$(mktemp -d)"
    CANNED="$STUBS/cleanup.out"     # what stub `brew bundle cleanup` prints
    ARGS_LOG="$STUBS/brew-args.log" # args passed to `brew bundle cleanup`
    STDIN_LOG="$STUBS/brew-stdin"   # what got piped into `brew bundle cleanup`
    UNINSTALL_LOG="$STUBS/uninstall.log"
    DATA_JSON_FILE="$STUBS/data.json" # what stub `chezmoi data` prints

    # Default machine: macApps on, appleDev off — so the active set is core +
    # mac-apps. Tests that need another shape rewrite this file.
    cat >"$DATA_JSON_FILE" <<'EOF'
{
  "modules": ["macApps"],
  "brewfiles": {
    "core": "features/brew/Brewfile",
    "byModule": {
      "macApps": "features/brew/Brewfile.mac-apps",
      "appleDev": "features/brew/Brewfile.apple-dev"
    }
  }
}
EOF

    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
[ "\$1" = data ] && exec cat "$DATA_JSON_FILE"
exit 0
EOF

    # One cask + two formulae, then the cache-pruning section newer Homebrew
    # appends. The parser must stop at "Would `brew cleanup`:" — otherwise
    # every "Would remove: …/Caches/…" line leaks in as a bogus removal.
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
    [ -n "\${BREW_CLEANUP_STDERR:-}" ] && printf '%s\n' "\$BREW_CLEANUP_STDERR" >&2
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

    # stub mirrors real gum confirm (reads STDIN): one answer line per confirm.
    # If chez mirror ever feeds the package list on stdin again, gum would read
    # packages instead of these answers — that's the regression this catches.
    cat >"$STUBS/gum" <<'EOF'
#!/usr/bin/env bash
[ "$1" = confirm ] || exit 0
IFS= read -r ans || ans=""
[ "$ans" = yes ]
EOF
    chmod +x "$STUBS/brew" "$STUBS/gum" "$STUBS/chezmoi"
}

teardown() {
    [ -n "${FAKE:-}" ] && rm -rf "$FAKE"
    [ -n "${STUBS:-}" ] && rm -rf "$STUBS"
}

# The committed scripts are run directly. DOTFILES_DIR points them at the fake
# repo, so they read its Brewfiles and its stubbed `chezmoi data` while still
# sourcing the real core/ui.sh and lib/removals.sh — the code under test is the
# code that ships, not a copy of it.
#
# This used to sed the function bodies out of dot_zshrc.tmpl and eval them,
# because that was the only way to reach 155 lines of zsh living inside a Go
# template. Those lines are features/brew/mirror.sh now.

# Mirrors chez mirror's own tty guard, for the TTY-gated tests below.
have_tty() { { : </dev/tty; } >/dev/null 2>&1; }

# _stubbed CMD… — run under the stubbed PATH and the log paths the stubs use.
_stubbed() {
    run env \
        PATH="$STUBS:$PATH" \
        DOTFILES_DIR="$FAKE" \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" BREW_CLEANUP_STDERR="${BREW_CLEANUP_STDERR:-}" \
        DATA_JSON_FILE="$DATA_JSON_FILE" \
        "$@"
}

# run_mirror [args…] — the real chez mirror.
run_mirror() { _stubbed bash "$REPO_ROOT/features/brew/mirror.sh" "$@"; }

# run_removals [args…] — the shared resolver, called as the verbs call it.
run_removals() {
    _stubbed bash -c '. "$1/features/brew/lib/removals.sh"; shift; brew_removals "$@"' \
        _ "$REPO_ROOT" "$@"
}

# Negative assertions must go through these. A bare `! grep …` in the middle of
# a test body is exempt from set -e (POSIX: "the return value is being inverted
# with !"), so bats never sees it fail — the assertion silently passes no matter
# what the output contains.
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

# ─── brew_removals: the active tier set + parser (bugs lived here) ─────

@test "brew_removals parses cleanup output into <kind><TAB><name> rows" {
    run_removals "$FAKE"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(printf 'cask\torphan-app')" ]
    [ "${lines[1]}" = "$(printf 'formula\tbats-core')" ]
    [ "${lines[2]}" = "$(printf 'formula\torphan-cli')" ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "brew_removals stops at the cache-prune section (no leaked paths)" {
    run_removals "$FAKE"
    [ "$status" -eq 0 ]
    # The cache-prune section must never surface as a removal (parser bug regression).
    no_match_in "$output" 'Would remove'
    no_match_in "$output" 'Caches/Homebrew'
    no_match_in "$output" 'brew cleanup'
}

@test "brew_removals labels the untap section 'tap' without leaking its header" {
    # "Would untap:" entries must not inherit the preceding "formula" kind — the
    # bug that made chez mirror `brew uninstall "Would untap:"` and a bare tap name.
    cat >"$CANNED" <<'EOF'
Would uninstall formulae:
orphan-cli
Would untap:
acme/formulae
EOF
    run_removals "$FAKE"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(printf 'formula\torphan-cli')" ]
    [ "${lines[1]}" = "$(printf 'tap\tacme/formulae')" ]
    [ "${#lines[@]}" -eq 2 ]
    no_match_in "$output" 'Would untap' # the header itself must never leak
}

@test "brew_removals feeds EVERY active tier to brew (multi-tier regression)" {
    run_removals "$FAKE"
    [ "$status" -eq 0 ]
    # Each active tier's marker must reach brew's stdin — not just the last
    # file's. Missing one reports its packages as untracked and queues the
    # toolchain for uninstall.
    for m in marker-core marker-macapps; do
        grep -qF "$m" "$STDIN_LOG" || {
            echo "missing $m from brew stdin:"
            cat "$STDIN_LOG"
            return 1
        }
    done
}

@test "brew_removals ignores a Brewfile no tier declares (no globbing)" {
    # The bug: the tier set was the `Brewfile.*` glob, so any stray file counted
    # as tracked — a cask moved out of a tier was never offered for removal on
    # the machine that just dropped it. Only the resolver's answer may be fed in.
    printf 'brew "marker-stray"\n' >"$FAKE/features/brew/Brewfile.stray"
    run_removals "$FAKE"
    [ "$status" -eq 0 ]
    no_match 'marker-stray' "$STDIN_LOG"
}

@test "brew_removals excludes a disabled module's tier" {
    printf 'brew "marker-appledev"\n' >"$FAKE/features/brew/Brewfile.apple-dev"
    # appleDev is absent from .modules in the default stub data.
    run_removals "$FAKE"
    [ "$status" -eq 0 ]
    no_match 'marker-appledev' "$STDIN_LOG"
}

@test "brew_removals includes a module tier once its module is enabled" {
    # The other half of the same rule, and the apple-dev regression from #72: a
    # tier the machine DOES have enabled must never read as untracked.
    printf 'brew "marker-appledev"\n' >"$FAKE/features/brew/Brewfile.apple-dev"
    jq '.modules += ["appleDev"]' "$DATA_JSON_FILE" >"$DATA_JSON_FILE.new"
    mv "$DATA_JSON_FILE.new" "$DATA_JSON_FILE"
    run_removals "$FAKE"
    [ "$status" -eq 0 ]
    grep -qF marker-appledev "$STDIN_LOG" || {
        echo "the enabled apple-dev tier never reached brew stdin:"
        cat "$STDIN_LOG"
        return 1
    }
}

@test "brew_removals fails closed on a config the v1.0 migration has not reached" {
    # A Mac that has pulled v1.0 but not yet applied still has `profile` saved,
    # and its work stack is declared by nothing in the repo any more. Resolving
    # anyway would offer that whole stack for uninstall, so the resolver refuses
    # — and refusing must reach all the way out here, as an empty removal set.
    jq '.profile = "work"' "$DATA_JSON_FILE" >"$DATA_JSON_FILE.new"
    mv "$DATA_JSON_FILE.new" "$DATA_JSON_FILE"
    run_removals "$FAKE"
    [ "$status" -eq 1 ]
    [ ! -s "$ARGS_LOG" ] # brew was never even asked
    grep -qF 'could not resolve the active Brewfiles' <<<"$output"
}

@test "brew_removals fails closed when the tier set cannot be resolved" {
    # Fail-closed matters more than fail-loud here: an empty/garbage resolve
    # must yield NO removal set, never a bigger one. brew must not even run.
    : >"$DATA_JSON_FILE"
    run_removals "$FAKE"
    [ "$status" -eq 1 ]
    [ ! -s "$ARGS_LOG" ]
    grep -qF 'could not resolve the active Brewfiles' <<<"$output"
}

@test "brew_removals fails closed when the resolver lib is missing" {
    rm -f "$FAKE/features/brew/lib/tiers.sh"
    run_removals "$FAKE"
    [ "$status" -eq 1 ]
    [ ! -s "$ARGS_LOG" ]
    grep -qF 'cannot resolve the active Brewfiles' <<<"$output"
}

@test "brew_removals passes a single --file=- (never multiple --file)" {
    run_removals "$FAKE"
    [ "$status" -eq 0 ]
    [ "$(cat "$ARGS_LOG")" = "cleanup --file=-" ]
    # Belt-and-braces: exactly one --file token — the whole point of the fix.
    [ "$(grep -o -- '--file' "$ARGS_LOG" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "brew_removals yields nothing when brew reports no removals" {
    : >"$CANNED" # brew bundle cleanup prints nothing
    run_removals "$FAKE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "brew_removals warns on a genuine brew Error: but still returns the removal set" {
    # Regression: an untrusted-tap load failure (or any other real brew
    # failure) writes `Error: …` to stderr. Must surface as a loud warning,
    # not silently look identical to \"nothing to remove\".
    BREW_CLEANUP_STDERR='Error: Refusing to load formula acme/tap/thing from untrusted tap acme/tap.' \
        run_removals "$FAKE" 2>&1 1>/dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"reported errors"* ]] || return 1
    [[ "$output" == *"Error: Refusing to load formula"* ]] || return 1
}

@test "brew_removals stays silent on benign brew stderr noise (cache refresh, warnings)" {
    # brew routinely writes non-fatal progress/deprecation notices to stderr
    # even on a fully successful run — these must never trigger the warning.
    BREW_CLEANUP_STDERR='==> Downloading Homebrew API data' \
        run_removals "$FAKE" 2>&1 1>/dev/null
    [ "$status" -eq 0 ]
    [[ "$output" != *"reported errors"* ]] || return 1
}

# ─── brew_uninstall_one: cask-vs-formula dispatch ─────────────────────

@test "brew_uninstall_one routes casks through --cask, formulae plain" {
    _stubbed bash -c '. "$1/features/brew/lib/removals.sh"
        brew_uninstall_one cask my-app
        brew_uninstall_one formula my-cli' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "$UNINSTALL_LOG")" = "--cask my-app" ]
    [ "$(sed -n 2p "$UNINSTALL_LOG")" = "my-cli" ]
}

@test "brew_uninstall_one routes taps through untap (never uninstall)" {
    _stubbed bash -c '. "$1/features/brew/lib/removals.sh"
        brew_uninstall_one tap acme/formulae' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [ "$(cat "$UNINSTALL_LOG")" = "untap acme/formulae" ]
}

# ─── chez mirror: end-to-end behaviour ───────────────────────────────────────

@test "chez mirror refuses to call the set clean when it could not resolve it" {
    # An empty removal set has two very different causes. Reporting the
    # unresolvable one as "✓ every installed package is tracked" would be a
    # false all-clear on exactly the machine that needs looking at.
    : >"$DATA_JSON_FILE"
    run_mirror
    [ "$status" -eq 1 ]
    no_match_in "$output" 'nothing to remove'
    grep -qF 'could not determine what this machine tracks' <<<"$output"
    [ ! -s "$UNINSTALL_LOG" ]
}

@test "chez mirror reports nothing to remove when every package is tracked" {
    : >"$CANNED" # nothing untracked
    run_mirror
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to remove"* ]] || return 1
    [ ! -s "$UNINSTALL_LOG" ] # never uninstalled anything
}

@test "chez mirror refuses to uninstall without a controlling terminal (safety)" {
    have_tty && skip "has a controlling tty; see the confirm-loop test instead"
    run_mirror
    [ "$status" -eq 0 ]
    [[ "$output" == *"No TTY"* ]] || return 1
    [[ "$output" == *"orphan-app"* ]] || return 1
    [ ! -s "$UNINSTALL_LOG" ]
}

@test "chez mirror uninstalls only the confirmed packages, one at a time" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # Regression test: confirm cask, decline bats-core, confirm the other formula.
    # If chez mirror ever feeds the package list on stdin again, gum reads
    # packages instead of these answers and the loop miscounts.
    run env \
        PATH="$STUBS:$PATH" \
        DOTFILES_DIR="$FAKE" DATA_JSON_FILE="$DATA_JSON_FILE" \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash "$REPO_ROOT/features/brew/mirror.sh" <<<$'yes\nno\nyes'
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "$UNINSTALL_LOG")" = "--cask orphan-app" ]
    [ "$(sed -n 2p "$UNINSTALL_LOG")" = "orphan-cli" ]
    [ "$(wc -l <"$UNINSTALL_LOG" | tr -d ' ')" -eq 2 ]
    no_match '^bats-core$' "$UNINSTALL_LOG"
    [[ "$output" == *"removed 2 · kept 1"* ]] || return 1
}

# ─── chez mirror accept-all mode (--all / --yes / YES=1) ─────────────────────

@test "chez mirror --help prints usage and removes nothing" {
    run_mirror --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: chez mirror"* ]] || return 1
    [[ "$output" == *"--all"* ]] || return 1
    [ ! -s "$UNINSTALL_LOG" ] # help path never touches brew
}

@test "chez mirror --dry-run previews the untracked set and removes nothing" {
    run_mirror --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"orphan-app"* ]] || return 1
    [[ "$output" == *"DRY_RUN"* ]] || return 1
    [ ! -s "$UNINSTALL_LOG" ] # dry-run never touches brew
}

@test "DRY_RUN=1 chez mirror previews the same as --dry-run/-n" {
    run env \
        PATH="$STUBS:$PATH" \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" DRY_RUN=1 \
        bash "$REPO_ROOT/features/brew/mirror.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"orphan-app"* ]] || return 1
    [[ "$output" == *"DRY_RUN"* ]] || return 1
    [ ! -s "$UNINSTALL_LOG" ]
}

@test "chez mirror rejects an unknown option (exit 2, no uninstall)" {
    run_mirror --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option"* ]] || return 1
    [ ! -s "$UNINSTALL_LOG" ]
}

@test "chez mirror --all uninstalls the whole set after ONE confirmation" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # One 'yes' gates the whole batch; the per-package loop then runs unattended.
    run env \
        PATH="$STUBS:$PATH" \
        DOTFILES_DIR="$FAKE" DATA_JSON_FILE="$DATA_JSON_FILE" \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash "$REPO_ROOT/features/brew/mirror.sh" --all <<<$'yes'
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "$UNINSTALL_LOG")" = "--cask orphan-app" ]
    [ "$(sed -n 2p "$UNINSTALL_LOG")" = "bats-core" ]
    [ "$(sed -n 3p "$UNINSTALL_LOG")" = "orphan-cli" ]
    [ "$(wc -l <"$UNINSTALL_LOG" | tr -d ' ')" -eq 3 ]
    [[ "$output" == *"removed 3 · kept 0"* ]] || return 1
}

@test "chez mirror --all aborts cleanly when the bulk confirm is declined" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    run env \
        PATH="$STUBS:$PATH" \
        DOTFILES_DIR="$FAKE" DATA_JSON_FILE="$DATA_JSON_FILE" \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash "$REPO_ROOT/features/brew/mirror.sh" --all <<<$'no'
    [ "$status" -eq 0 ]
    [[ "$output" == *"aborted"* ]] || return 1
    [ ! -s "$UNINSTALL_LOG" ]
}

@test "YES=1 chez mirror accepts all with no prompt at all" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # YES=1 must never read stdin — a stray read would hang; </dev/null proves it.
    run env \
        PATH="$STUBS:$PATH" YES=1 \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash "$REPO_ROOT/features/brew/mirror.sh" </dev/null
    [ "$status" -eq 0 ]
    [ "$(wc -l <"$UNINSTALL_LOG" | tr -d ' ')" -eq 3 ]
    [[ "$output" == *"removed 3 · kept 0"* ]] || return 1
}

@test "chez mirror removes an interdependent set despite deps-first order (retry passes)" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # `brew bundle cleanup` lists a dependency BEFORE its dependent, so a one-shot
    # uninstall fails on the dep ("still required by …") — the retry-in-passes
    # loop must still clear both. libpng refuses until cairo is gone.
    cat >"$CANNED" <<'EOF'
Would uninstall formulae:
libpng
cairo
EOF
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
        bash "$REPO_ROOT/features/brew/mirror.sh" </dev/null
    [ "$status" -eq 0 ]
    # A non-final `[[ … ]]` never fails a bats test (set -e skips it), so every
    # assertion here uses `[ … ]`/`grep` instead — a no-op `[[ … ]]` would let
    # a regression pass silently.
    [ "$(sed -n 1p "$UNINSTALL_LOG")" = "cairo" ]
    [ "$(sed -n 2p "$UNINSTALL_LOG")" = "libpng" ]
    [ "$(wc -l <"$UNINSTALL_LOG" | tr -d ' ')" -eq 2 ]
    grep -qF "removed 2 · kept 0" <<<"$output"
    [ "$(grep -cF "still installed" <<<"$output")" -eq 0 ] # nothing left stuck
}

@test "chez mirror reports a package it can never remove instead of erroring out" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # libpng can never be uninstalled; zlib removes fine. The retry loop must
    # remove zlib, give up on libpng after a no-progress pass (no infinite loop).
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
        bash "$REPO_ROOT/features/brew/mirror.sh" </dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$UNINSTALL_LOG")" = "zlib" ]     # only zlib actually left
    grep -qF "still installed" <<<"$output"
    grep -qF "libpng" <<<"$output"
    grep -qF "removed 1 · kept 0" <<<"$output"  # stuck ≠ kept (kept is declined only)
}

# ─── chez mirror: brew autoremove of orphaned dependencies ───────────────────
# After the removal pass, chez mirror prunes formulae installed as dependencies
# nothing needs any more: preview via `brew autoremove -n`, then run it for
# real — accept-all under --all/YES=1, else behind one confirm.

# `autoremove -n` reports ORPHANS; `autoremove` (no -n) records that it ran.
_stub_brew_with_orphan() { # $1 = AUTOREMOVE_LOG path
    local log="$1"
    cat >"$STUBS/brew" <<EOF
#!/usr/bin/env bash
if [ "\$1" = bundle ] && [ "\$2" = cleanup ]; then
    cat >/dev/null
    cat "$CANNED" 2>/dev/null
    exit 0
fi
if [ "\$1" = uninstall ]; then
    shift
    printf '%s\n' "\$*" >>"$UNINSTALL_LOG"
    exit 0
fi
if [ "\$1" = autoremove ]; then
    if [ "\$2" = -n ]; then
        printf '==> Would autoremove 1 unneeded formula:\nleftover-dep\n'
    else
        printf 'ran\n' >>"$log"
    fi
    exit 0
fi
exit 0
EOF
    chmod +x "$STUBS/brew"
}

@test "chez mirror prunes orphaned dependencies via brew autoremove (YES=1, accept-all)" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    AUTOREMOVE_LOG="$STUBS/autoremove.log"
    _stub_brew_with_orphan "$AUTOREMOVE_LOG"
    run env \
        PATH="$STUBS:$PATH" YES=1 \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash "$REPO_ROOT/features/brew/mirror.sh" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed 3 · kept 0"* ]] || return 1
    [[ "$output" == *"leftover-dep"* ]]                  # the orphan was previewed
    [[ "$output" == *"pruned orphaned dependencies"* ]] || return 1
    [ -f "$AUTOREMOVE_LOG" ]                             # `brew autoremove` actually ran
    grep -qx "ran" "$AUTOREMOVE_LOG"
}

@test "chez mirror leaves orphaned deps alone when the autoremove confirm is declined" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    AUTOREMOVE_LOG="$STUBS/autoremove.log"
    _stub_brew_with_orphan "$AUTOREMOVE_LOG"
    # Three package confirms, then the autoremove confirm — decline the last.
    run env \
        PATH="$STUBS:$PATH" \
        DOTFILES_DIR="$FAKE" DATA_JSON_FILE="$DATA_JSON_FILE" \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash "$REPO_ROOT/features/brew/mirror.sh" <<<$'yes\nyes\nyes\nno'
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed 3 · kept 0"* ]] || return 1
    [[ "$output" == *"kept orphaned dependencies"* ]] || return 1
    [ ! -f "$AUTOREMOVE_LOG" ]                           # prune declined ⇒ never ran
}

@test "chez mirror skips brew autoremove when nothing is orphaned (YES=1)" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    AUTOREMOVE_LOG="$STUBS/autoremove.log"
    # Header-only output (0 unneeded, no bare names) must read as "no orphans".
    cat >"$STUBS/brew" <<EOF
#!/usr/bin/env bash
if [ "\$1" = bundle ] && [ "\$2" = cleanup ]; then cat >/dev/null; cat "$CANNED" 2>/dev/null; exit 0; fi
if [ "\$1" = uninstall ]; then shift; printf '%s\n' "\$*" >>"$UNINSTALL_LOG"; exit 0; fi
if [ "\$1" = autoremove ]; then
    [ "\$2" = -n ] && { printf '==> Autoremoving 0 unneeded formulae\n'; exit 0; }
    printf 'ran\n' >>"$AUTOREMOVE_LOG"; exit 0
fi
exit 0
EOF
    chmod +x "$STUBS/brew"
    run env \
        PATH="$STUBS:$PATH" YES=1 \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash "$REPO_ROOT/features/brew/mirror.sh" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed 3 · kept 0"* ]] || return 1
    [[ "$output" != *"Orphaned dependencies"* ]]         # nothing surfaced
    [ ! -f "$AUTOREMOVE_LOG" ]                           # prune never ran
}

@test "chez mirror untaps an untracked tap end-to-end (Would untap regression)" {
    have_tty || skip "no controlling tty (headless/CI); run under: script -q /dev/null bats …"
    # Pre-fix, a tap-only preview fed `brew uninstall "Would untap:"` (errored).
    cat >"$CANNED" <<'EOF'
Would untap:
acme/formulae
EOF
    run env \
        PATH="$STUBS:$PATH" YES=1 \
        CANNED="$CANNED" ARGS_LOG="$ARGS_LOG" STDIN_LOG="$STDIN_LOG" \
        UNINSTALL_LOG="$UNINSTALL_LOG" \
        bash "$REPO_ROOT/features/brew/mirror.sh" </dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$UNINSTALL_LOG")" = "untap acme/formulae" ]
    [[ "$output" == *"removed 1 · kept 0"* ]] || return 1
}
