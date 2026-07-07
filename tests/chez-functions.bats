#!/usr/bin/env bats
# Behavioural tests for the zsh dotfiles meta-commands that aren't the Brewfile
# reconciler (that one is covered end-to-end in chezmirror.bats):
#   _chez_run          — the self-heal wrapper behind chezup/chezdoctor/macos-defaults
#   _chez_brew_untracked / chezaudit — the read-only "what did I install off-book?" drift report
#   chez               — the smart `chezmoi apply` wrapper (status gate + apply + drift notice)
#
# Like shell-functions.bats and chezmirror.bats, these EXTRACT the real function
# bodies from the committed template and run them (under zsh) against stubbed
# chezmoi/brew, repointing the apply-time `local src={{ … }}` line at a fake repo.
# A regression in the committed source therefore fails here — we never re-declare
# a copy of the logic.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"

    FAKE="$(mktemp -d)"
    mkdir -p "$FAKE/packages" "$FAKE/scripts/bin"
    # All four Brewfile tiers, matching the real repo: _chez_brew_untracked globs
    # `Brewfile.*`, and zsh's NOMATCH would abort the read if the tiers were
    # absent. One tracked formula (git); `brew leaves` (stubbed) decides drift.
    printf 'brew "git"\n' >"$FAKE/packages/Brewfile"
    : >"$FAKE/packages/Brewfile.mac-apps"
    : >"$FAKE/packages/Brewfile.personal"
    : >"$FAKE/packages/Brewfile.work"

    STUBS="$(mktemp -d)"
    APPLY_LOG="$STUBS/apply.log"

    # chezmoi stub: `status` prints CHEZMOI_STATUS (empty = clean); `apply`
    # records its args and honours CHEZMOI_APPLY_RC.
    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
if [ "\$1" = status ]; then printf '%s' "\${CHEZMOI_STATUS:-}"; exit 0; fi
if [ "\$1" = apply ]; then shift; printf 'apply %s\n' "\$*" >>"$APPLY_LOG"; exit "\${CHEZMOI_APPLY_RC:-0}"; fi
exit 0
EOF
    # brew stub: `leaves` prints BREW_LEAVES (chezaudit/chez); `bundle cleanup`
    # consumes the piped-in tier union and echoes BREW_CLEANUP_OUT (chezbump);
    # update/upgrade are no-ops. Covers every brew call these functions make.
    cat >"$STUBS/brew" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = leaves ]; then printf '%s\n' ${BREW_LEAVES:-}; exit 0; fi
if [ "$1" = bundle ] && [ "$2" = cleanup ]; then
    cat >/dev/null                                   # swallow the piped tiers
    [ -n "${BREW_CLEANUP_OUT:-}" ] && [ -f "$BREW_CLEANUP_OUT" ] && cat "$BREW_CLEANUP_OUT"
    exit 0
fi
exit 0
EOF
    # mise stub so chezbump's `mise upgrade` never reaches the real (networked)
    # global runtime upgrade; `command -v mise` still resolves it.
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
    run env PATH="$STUBS:$PATH" APPLY_LOG="$APPLY_LOG" \
        BREW_LEAVES="${BREW_LEAVES:-}" BREW_CLEANUP_OUT="${BREW_CLEANUP_OUT:-}" \
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
    # Hide chezmoi so the self-heal can't run: it must degrade to a
    # copy-pasteable manual recovery line and return non-zero, never wedge.
    # /usr/bin:/bin has zsh + coreutils but not Homebrew's chezmoi.
    PATH="/usr/bin:/bin" command -v chezmoi >/dev/null 2>&1 && skip "chezmoi on system PATH"
    run env PATH="/usr/bin:/bin" APPLY_LOG="$APPLY_LOG" \
        zsh -c "$(extract _chez_run); _chez_run scripts/bin/gone.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is missing"* ]]
    [[ "$output" == *"fix by hand"* ]]
    [ ! -s "$APPLY_LOG" ]  # never applied
}

# ─── _chez_brew_untracked / chezaudit: read-only drift report ────────────────

@test "_chez_brew_untracked lists leaves that are in no Brewfile" {
    BREW_LEAVES=$'git\njq\nripgrep' \
        run_zsh "$(extract _chez_brew_untracked); _chez_brew_untracked"
    [ "$status" -eq 0 ]
    # git is tracked (in the fake Brewfile); jq + ripgrep are not.
    [[ "$output" != *git* ]]
    [[ "$output" == *jq* ]]
    [[ "$output" == *ripgrep* ]]
}

@test "_chez_brew_untracked treats a tap-qualified leaf as tracked (both sides normalised)" {
    # Regression: tap formulae surface tap-qualified from `brew leaves`
    # (hashicorp/tap/terraform) while the Brewfile lists them the same way. The
    # tracked side was reduced to the bare leaf name but the leaves side was not,
    # so every tap-installed-and-tracked package was a phantom "untracked" hit.
    # The Azure entry also proves the tap-prefix case is irrelevant: the Brewfile
    # capitalises it (Azure/…) while `brew leaves` lowercases it (azure/…) — both
    # collapse to the bare leaf, so neither should be reported.
    printf 'brew "hashicorp/tap/terraform"\nbrew "Azure/kubelogin/kubelogin"\n' \
        >>"$FAKE/packages/Brewfile.work"
    BREW_LEAVES=$'git\nhashicorp/tap/terraform\nazure/kubelogin/kubelogin' \
        run_zsh "$(extract _chez_brew_untracked); _chez_brew_untracked"
    [ "$status" -eq 0 ]
    [[ "$output" != *terraform* ]]
    [[ "$output" != *kubelogin* ]]
}

@test "_chez_brew_untracked still flags a tap leaf that is in no Brewfile" {
    # The normalisation must not swallow genuine drift: an untracked tap formula
    # is reported by its bare leaf name (not the tap path).
    BREW_LEAVES=$'git\nhashicorp/tap/packer' \
        run_zsh "$(extract _chez_brew_untracked); _chez_brew_untracked"
    [ "$status" -eq 0 ]
    [[ "$output" == *packer* ]]
    [[ "$output" != *hashicorp* ]]  # reported as the bare leaf, not the tap path
}

@test "chezaudit reports a clean machine when every leaf is tracked" {
    BREW_LEAVES=$'git' \
        run_zsh "$(extract chezaudit _chez_brew_untracked); chezaudit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no untracked brew packages"* ]]
}

@test "chezaudit lists the untracked packages and points at chezmirror" {
    BREW_LEAVES=$'git\njq' \
        run_zsh "$(extract chezaudit _chez_brew_untracked); chezaudit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Untracked"* ]]
    [[ "$output" == *"jq"* ]]
    [[ "$output" == *"chezmirror"* ]]
}

# ─── chez: the smart apply wrapper ──────────────────────────────────────────

@test "chez applies without prompting when there is no drift" {
    # Empty status ⇒ no confirmation gate, straight to `chezmoi apply --force`.
    CHEZMOI_STATUS="" BREW_LEAVES=$'git' \
        run_zsh "$(extract chez _chez_brew_untracked); chez"
    [ "$status" -eq 0 ]
    grep -q 'apply --force' "$APPLY_LOG"
}

@test "chez surfaces a Brewfile-removal drift notice after applying" {
    # A leaf tracked in no Brewfile ⇒ the informational notice fires and names
    # chezmirror as the reconcile path — but chez itself never uninstalls.
    CHEZMOI_STATUS="" BREW_LEAVES=$'git\njq' \
        run_zsh "$(extract chez _chez_brew_untracked); chez"
    [ "$status" -eq 0 ]
    [[ "$output" == *"in no Brewfile"* ]]
    [[ "$output" == *"chezmirror"* ]]
}

@test "chez does not raise a phantom drift notice for a tracked tap leaf" {
    # End-to-end guard: a tap formula tracked in the Brewfile must not trip the
    # post-apply "installed locally but in no Brewfile" notice.
    printf 'brew "hashicorp/tap/terraform"\n' >>"$FAKE/packages/Brewfile.work"
    CHEZMOI_STATUS="" BREW_LEAVES=$'git\nhashicorp/tap/terraform' \
        run_zsh "$(extract chez _chez_brew_untracked); chez"
    [ "$status" -eq 0 ]
    [[ "$output" != *"in no Brewfile"* ]]
}

@test "chez propagates a failing apply's exit code" {
    CHEZMOI_STATUS="" CHEZMOI_APPLY_RC=3 BREW_LEAVES=$'git' \
        run_zsh "$(extract chez _chez_brew_untracked); chez"
    [ "$status" -eq 3 ]
}

# ─── dotfiles: the no-arg control panel ─────────────────────────────────────

# bats runs under bash 3.2 (no negative array indices), so the trailing `pwd`
# is read via an explicit last index rather than ${lines[-1]}.
@test "dotfiles with no args cds into the source repo" {
    run_zsh "$(extract dotfiles); dotfiles; pwd"
    [ "$status" -eq 0 ]
    [ "${lines[$((${#lines[@]} - 1))]}" = "$FAKE" ]
}

@test "dotfiles with an argument prints reset/reinit guidance without cd-ing" {
    run_zsh "$(extract dotfiles); cd '$STUBS'; dotfiles help; pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"chezreset"* ]]
    [[ "$output" == *"chezreinit"* ]]
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
