#!/usr/bin/env bats
# Tests for the zsh dotfiles meta-commands not covered by chezmirror.bats:
#   chezapply   — the smart `chezmoi apply` wrapper (status gate + apply + drift notice)
#   chezstatus  — read-only file-drift + untracked-package report
#   dotfiles    — the no-arg control panel
#   chezbump    — routine dependency-bump previewer
#
# These extract the real function bodies from the committed template and run
# them (under zsh) against stubbed chezmoi/brew, repointing the apply-time
# `local src={{ … }}` line at a fake repo — a regression in the committed
# source fails here directly.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"

    FAKE="$(mktemp -d)"
    mkdir -p "$FAKE/packages" "$FAKE/scripts/bin"
    # All four tiers must exist — zsh's NOMATCH would abort _chez_brew_removals's
    # `Brewfile.*` glob read otherwise.
    printf 'brew "git"\n' >"$FAKE/packages/Brewfile"
    : >"$FAKE/packages/Brewfile.mac-apps"
    : >"$FAKE/packages/Brewfile.personal"
    : >"$FAKE/packages/Brewfile.work"

    STUBS="$(mktemp -d)"
    APPLY_LOG="$STUBS/apply.log"
    DIFF_LOG="$STUBS/diff.log"

    # chezmoi stub: status prints CHEZMOI_STATUS; apply records args and honours
    # CHEZMOI_APPLY_RC; diff records args (chezstatus's raw-passthrough path).
    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
if [ "\$1" = status ]; then printf '%s' "\${CHEZMOI_STATUS:-}"; exit 0; fi
if [ "\$1" = apply ]; then shift; printf 'apply %s\n' "\$*" >>"$APPLY_LOG"; exit "\${CHEZMOI_APPLY_RC:-0}"; fi
if [ "\$1" = diff ]; then shift; printf 'diff %s\n' "\$*" >>"$DIFF_LOG"; exit 0; fi
exit 0
EOF
    # brew stub: bundle cleanup consumes the piped tier union and echoes
    # BREW_CLEANUP_OUT; trust/update/upgrade are no-ops.
    cat >"$STUBS/brew" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = bundle ] && [ "$2" = cleanup ]; then
    cat >/dev/null                                   # swallow the piped tiers
    [ -n "${BREW_CLEANUP_OUT:-}" ] && [ -f "$BREW_CLEANUP_OUT" ] && cat "$BREW_CLEANUP_OUT"
    exit 0
fi
exit 0
EOF
    # mise stub so chezbump's `mise upgrade` never hits the real network call.
    printf '#!/usr/bin/env bash\nexit 0\n' >"$STUBS/mise"
    chmod +x "$STUBS/chezmoi" "$STUBS/brew" "$STUBS/mise"
}

teardown() {
    [ -n "${FAKE:-}" ] && rm -rf "$FAKE"
    [ -n "${STUBS:-}" ] && rm -rf "$STUBS"
}

# Extract one or more function bodies, repointing the baked src line at $FAKE.
extract() {
    local fn
    for fn in "$@"; do
        sed -n "/^${fn}() {/,/^}/p" "$ZSHRC"
    done | sed "s|^    local src={{.*}}|    local src=\"$FAKE\"|"
}

# Run a zsh snippet with the stub PATH and log paths exported.
run_zsh() {
    run env PATH="$STUBS:$PATH" APPLY_LOG="$APPLY_LOG" DIFF_LOG="$DIFF_LOG" \
        BREW_CLEANUP_OUT="${BREW_CLEANUP_OUT:-}" \
        CHEZMOI_STATUS="${CHEZMOI_STATUS:-}" CHEZMOI_APPLY_RC="${CHEZMOI_APPLY_RC:-0}" \
        zsh -c "$1"
}

# ─── _chez_run: the self-heal wrapper ───────────────────────────────────────

@test "_chez_run executes the target script and forwards its arguments" {
    cat >"$FAKE/scripts/bin/echo.sh" <<'EOF'
#!/usr/bin/env bash
echo "ran with: $*"
EOF
    run_zsh "$(extract _chez_run); _chez_run scripts/bin/echo.sh alpha beta"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran with: alpha beta"* ]]
}

@test "_chez_run on a missing script with no chezmoi tells you how to fix by hand" {
    # /usr/bin:/bin has zsh + coreutils but not Homebrew's chezmoi, so the
    # self-heal can't run — it must degrade to a manual recovery line, not wedge.
    PATH="/usr/bin:/bin" command -v chezmoi >/dev/null 2>&1 && skip "chezmoi on system PATH"
    run env PATH="/usr/bin:/bin" APPLY_LOG="$APPLY_LOG" \
        zsh -c "$(extract _chez_run); _chez_run scripts/bin/gone.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is missing"* ]]
    [[ "$output" == *"fix by hand"* ]]
    [ ! -s "$APPLY_LOG" ]  # never applied
}

# ─── chezapply: the smart apply wrapper ─────────────────────────────────────

@test "chezapply applies without prompting when there is no drift" {
    # Empty status ⇒ straight to `chezmoi apply --force`, no confirmation gate.
    CHEZMOI_STATUS="" \
        run_zsh "$(extract chezapply _chez_brew_removals); chezapply"
    [ "$status" -eq 0 ]
    grep -q 'apply --force' "$APPLY_LOG"
}

@test "chezapply surfaces a Brewfile-removal drift notice after applying, including casks" {
    # Notice names chezmirror as the reconcile path; chezapply itself never
    # uninstalls. Regression: the notice must use _chez_brew_removals (brew
    # bundle cleanup), not a `brew leaves`-only check — that older approach
    # missed casks entirely.
    cat >"$STUBS/cleanup.out" <<'OUT'
Would uninstall casks:
discord
Run `brew bundle cleanup --force` to make these changes.
OUT
    CHEZMOI_STATUS="" BREW_CLEANUP_OUT="$STUBS/cleanup.out" \
        run_zsh "$(extract chezapply _chez_brew_removals); chezapply"
    [ "$status" -eq 0 ]
    [[ "$output" == *"in no Brewfile"* ]]
    [[ "$output" == *"chezmirror"* ]]
}

@test "chezapply propagates a failing apply's exit code" {
    CHEZMOI_STATUS="" CHEZMOI_APPLY_RC=3 \
        run_zsh "$(extract chezapply _chez_brew_removals); chezapply"
    [ "$status" -eq 3 ]
}

# ─── chezstatus: read-only file + package drift explainer ──────────────────
# The status codes are two columns (left = local $HOME drift, right = repo →
# $HOME apply). chezstatus splits them into two labelled sections; these tests
# feed the stub a fixed CHEZMOI_STATUS and assert the plain-language grouping.

@test "chezstatus reports in-sync and no untracked packages when everything is clean" {
    CHEZMOI_STATUS="" \
        run_zsh "$(extract chezstatus _chez_brew_removals); chezstatus"
    [ "$status" -eq 0 ]
    [[ "$output" == *"in sync"* ]]
    [[ "$output" != *"Untracked Homebrew"* ]]
}

@test "chezstatus flags untracked casks, not just formulae, and points at chezmirror" {
    # Regression: the old chezaudit used `brew leaves`, which is formula-only
    # and silently missed untracked casks. chezstatus must not repeat that.
    cat >"$STUBS/cleanup.out" <<'OUT'
Would uninstall casks:
obs
Run `brew bundle cleanup --force` to make these changes.
OUT
    CHEZMOI_STATUS="" BREW_CLEANUP_OUT="$STUBS/cleanup.out" \
        run_zsh "$(extract chezstatus _chez_brew_removals); chezstatus"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Untracked Homebrew"* ]]
    [[ "$output" == *"cask"* ]]
    [[ "$output" == *"obs"* ]]
    [[ "$output" == *"chezmirror"* ]]
}

@test "chezstatus groups repo → \$HOME changes under the apply section with plain verbs" {
    # Right column drives the 'what chezapply would write' list: ' M' → modify,
    # ' A' → add. No local drift (left column blank) ⇒ no drift section.
    CHEZMOI_STATUS=$' M .config/zsh/.zshrc\n A .config/foo/bar' \
        run_zsh "$(extract chezstatus _chez_brew_removals); chezstatus"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Repo → \$HOME"* ]]
    [[ "$output" == *"modify"* ]]
    [[ "$output" == *".config/zsh/.zshrc"* ]]
    [[ "$output" == *"add"* ]]
    [[ "$output" == *".config/foo/bar"* ]]
    [[ "$output" != *"Local drift"* ]]  # nothing edited locally
}

@test "chezstatus surfaces local drift and the re-add hint" {
    # 'MM' = edited locally (left col) AND repo differs (right col): it must
    # appear under BOTH sections, and the drift section warns about overwrite.
    CHEZMOI_STATUS=$'MM .config/zsh/.zshrc' \
        run_zsh "$(extract chezstatus _chez_brew_removals); chezstatus"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Repo → \$HOME"* ]]
    [[ "$output" == *"Local drift"* ]]
    [[ "$output" == *"edited"* ]]
    [[ "$output" == *"re-add"* ]]
}

@test "chezstatus -v hands off to the raw \`chezmoi diff\`" {
    # Verbose (and any path arg) must bypass the summary entirely and shell out
    # to `chezmoi diff` — recorded in DIFF_LOG by the stub.
    CHEZMOI_STATUS=$'MM .config/zsh/.zshrc' \
        run_zsh "$(extract chezstatus); chezstatus -v"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Repo → \$HOME"* ]]  # took the passthrough, not the summary
    grep -q '^diff' "$DIFF_LOG"
}

@test "chezstatus PATH forwards the path to \`chezmoi diff\`" {
    run_zsh "$(extract chezstatus); chezstatus ~/.zshrc"
    [ "$status" -eq 0 ]
    grep -q 'diff .*\.zshrc' "$DIFF_LOG"
}

@test "chezstatus --help prints usage without touching chezmoi" {
    run_zsh "$(extract chezstatus); chezstatus --help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: chezstatus"* ]]
    [ ! -s "$DIFF_LOG" ]  # help path shells out to nothing
}

# ─── dotfiles: the no-arg control panel ─────────────────────────────────────

# bats runs under bash 3.2 (no negative array indices), so the trailing `pwd`
# is read via an explicit last index rather than ${lines[-1]}.
@test "dotfiles with no args cds into the source repo" {
    run_zsh "$(extract dotfiles); dotfiles; pwd"
    [ "$status" -eq 0 ]
    [ "${lines[$((${#lines[@]} - 1))]}" = "$FAKE" ]
}

@test "dotfiles with an argument prints chezsetup guidance without cd-ing" {
    run_zsh "$(extract dotfiles); cd '$STUBS'; dotfiles help; pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"chezsetup"* ]]
    [[ "$output" == *"chezsetup --reset"* ]]
    [ "${lines[$((${#lines[@]} - 1))]}" = "$STUBS" ]  # argument path must NOT cd
}

# ─── chezbump: routine dependency-bump previewer ────────────────────────────
# Only the untracked-removal PREVIEW is asserted (the interesting, shared logic);
# brew update/upgrade + mise upgrade are stubbed no-ops.

@test "chezbump previews the untracked removal set and points at chezmirror" {
    cat >"$STUBS/cleanup.out" <<'OUT'
Would uninstall formulae:
orphan-cli
Run `brew bundle cleanup --force` to make these changes.
OUT
    BREW_CLEANUP_OUT="$STUBS/cleanup.out" \
        run_zsh "$(extract chezbump _chez_brew_removals); chezbump"
    [ "$status" -eq 0 ]
    [[ "$output" == *"formula"* ]]
    [[ "$output" == *"orphan-cli"* ]]
    [[ "$output" == *"chezmirror"* ]]  # reconcile hint
}

@test "chezbump reports a fully-tracked machine when nothing is untracked" {
    : >"$STUBS/cleanup.out"  # brew bundle cleanup finds nothing to remove
    BREW_CLEANUP_OUT="$STUBS/cleanup.out" \
        run_zsh "$(extract chezbump _chez_brew_removals); chezbump"
    [ "$status" -eq 0 ]
    [[ "$output" == *"every installed package is tracked"* ]]
}
