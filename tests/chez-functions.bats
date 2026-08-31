#!/usr/bin/env bats
# The zsh half of the command surface: `_chez_run` and the `chez` dispatcher.
#
# Everything else about dispatch is bash and lives in tests/chez.bats. What can
# only be tested here is what has to be a shell function — `chez cd` changing
# the caller's directory — and the hand-off into bash.
#
# These extract the real function bodies from the committed template and run
# them (under zsh) against stubbed chezmoi/brew, repointing the apply-time
# `local src={{ … }}` line at a fake repo — a regression in the committed
# source fails here directly.

setup() {
    load '../core/testing/helper'
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"

    command -v jq >/dev/null 2>&1 || skip "jq not installed (brew_active_files needs it)"

    FAKE="$(mktemp -d)"
    mkdir -p "$FAKE/features/brew/lib" "$FAKE/scripts/bin"
    # The real resolver, so these zsh-side tests exercise the committed lib —
    # _chez_brew_removals sources it out of the repo root it's handed.
    cp "$REPO_ROOT/features/brew/lib/tiers.sh" "$FAKE/features/brew/lib/tiers.sh"
    # chez apply / chez status reach the resolver through the same lib the
    # extracted verbs do, so the fake repo has to carry it too.
    cp "$REPO_ROOT/features/brew/lib/removals.sh" "$FAKE/features/brew/lib/removals.sh"
    printf 'brew "git"\n' >"$FAKE/features/brew/Brewfile"
    : >"$FAKE/features/brew/Brewfile.mac-apps"
    : >"$FAKE/features/brew/Brewfile.personal"
    : >"$FAKE/features/brew/Brewfile.work"

    STUBS="$(mktemp -d)"
    APPLY_LOG="$STUBS/apply.log"
    DIFF_LOG="$STUBS/diff.log"
    DATA_JSON_FILE="$STUBS/data.json"

    # A personal machine with macApps on — so mac-apps + personal are active
    # tiers and Brewfile.work is not.
    cat >"$DATA_JSON_FILE" <<'EOF'
{
  "profile": "personal",
  "modules": ["macApps"],
  "brewfiles": {
    "core": "features/brew/Brewfile",
    "byModule": {"macApps": "features/brew/Brewfile.mac-apps"},
    "byProfile": {
      "personal": "features/brew/Brewfile.personal",
      "work": "features/brew/Brewfile.work"
    }
  }
}
EOF

    # chezmoi stub: status prints CHEZMOI_STATUS; apply records args and honours
    # CHEZMOI_APPLY_RC; diff records args (chez status's raw-passthrough path);
    # data feeds the Brewfile-tier resolver.
    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
if [ "\$1" = status ]; then printf '%s' "\${CHEZMOI_STATUS:-}"; exit 0; fi
if [ "\$1" = apply ]; then shift; printf 'apply %s\n' "\$*" >>"$APPLY_LOG"; exit "\${CHEZMOI_APPLY_RC:-0}"; fi
if [ "\$1" = diff ]; then shift; printf 'diff %s\n' "\$*" >>"$DIFF_LOG"; exit 0; fi
if [ "\$1" = data ]; then exec cat "$DATA_JSON_FILE"; fi
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
    # mise stub so chez bump's `mise upgrade` never hits the real network call.
    printf '#!/usr/bin/env bash\nexit 0\n' >"$STUBS/mise"
    chmod +x "$STUBS/chezmoi" "$STUBS/brew" "$STUBS/mise"
}

teardown() {
    [ -n "${FAKE:-}" ] && rm -rf "$FAKE"
    [ -n "${STUBS:-}" ] && rm -rf "$STUBS"
}

# Extract one or more function bodies, replacing the two lines chezmoi renders
# at apply time — the repo path and the module set — with test values. Both
# carry Go-template braces, which zsh cannot parse, so a missed one shows up as
# a parse error rather than a wrong result.
extract() {
    local fn
    for fn in "$@"; do
        sed -n "/^${fn}() {/,/^}/p" "$ZSHRC"
    done |
        sed -e "s|^    local src={{.*}}|    local src=\"$FAKE\"|" \
            -e "s|^    local -x CHEZ_MODULES={{.*}}|    local -x CHEZ_MODULES=\"${MODULES_STUB-}\"|"
}

# Run a zsh snippet with the stub PATH and log paths exported.
run_zsh() {
    run env PATH="$STUBS:$PATH" APPLY_LOG="$APPLY_LOG" DIFF_LOG="$DIFF_LOG" \
        DATA_JSON_FILE="$DATA_JSON_FILE" \
        BREW_CLEANUP_OUT="${BREW_CLEANUP_OUT:-}" \
        CHEZMOI_STATUS="${CHEZMOI_STATUS:-}" CHEZMOI_APPLY_RC="${CHEZMOI_APPLY_RC:-0}" \
        zsh -c "$1"
}

# The verbs that have moved out of the template are run as the scripts they are,
# against the fake repo. Only the ones still inline need run_zsh.
run_bash() {
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$FAKE" \
        DATA_JSON_FILE="$DATA_JSON_FILE" \
        BREW_CLEANUP_OUT="${BREW_CLEANUP_OUT:-}" \
        bash "$@"
}

# ─── _chez_run: the self-heal wrapper ───────────────────────────────────────

@test "_chez_run executes the target script and forwards its arguments" {
    cat >"$FAKE/scripts/bin/echo.sh" <<'EOF'
#!/usr/bin/env bash
echo "ran with: $*"
EOF
    run_zsh "$(extract _chez_run); _chez_run scripts/bin/echo.sh alpha beta"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran with: alpha beta"* ]] || return 1
}

@test "_chez_run on a missing script with no chezmoi tells you how to fix by hand" {
    # /usr/bin:/bin has zsh + coreutils but not Homebrew's chezmoi, so the
    # self-heal can't run — it must degrade to a manual recovery line, not wedge.
    PATH="/usr/bin:/bin" command -v chezmoi >/dev/null 2>&1 && skip "chezmoi on system PATH"
    run env PATH="/usr/bin:/bin" APPLY_LOG="$APPLY_LOG" \
        zsh -c "$(extract _chez_run); _chez_run scripts/bin/gone.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is missing"* ]] || return 1
    [[ "$output" == *"fix by hand"* ]] || return 1
    [ ! -s "$APPLY_LOG" ]  # never applied
}

# ─── chez: the dispatcher, as zsh actually runs it ──────────────────────────
# tests/chez.bats drives core/chez.sh directly. What can only be checked here is
# the half that has to be a shell function: `chez cd` changing the caller's
# directory, and the delegation carrying its arguments and the module set into
# bash.

# bats runs under bash 3.2 (no negative array indices), so the trailing `pwd`
# is read via an explicit last index rather than ${lines[-1]}.
@test "chez cd changes the calling shell's directory" {
    run_zsh "$(extract chez); cd '$STUBS'; chez cd; pwd"
    [ "$status" -eq 0 ]
    [ "${lines[$((${#lines[@]} - 1))]}" = "$FAKE" ]
}

@test "every other verb is delegated, with its arguments intact" {
    mkdir -p "$FAKE/core"
    cat >"$FAKE/core/chez.sh" <<'EOF'
#!/usr/bin/env bash
printf 'dispatched: %s
' "$*"
EOF
    run_zsh "$(extract _chez_run chez); chez mirror --dry-run -v"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dispatched: mirror --dry-run -v"* ]] || return 1
}

@test "the delegation carries the rendered module set into bash" {
    mkdir -p "$FAKE/core"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "modules=[%s]\\n" "${CHEZ_MODULES-UNSET}"' >"$FAKE/core/chez.sh"
    run_zsh "$(MODULES_STUB='appleDev claudeDistiller' extract _chez_run chez); chez help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"modules=[appleDev claudeDistiller]"* ]] || return 1
}

@test "a Mac with no modules still exports the variable rather than leaving it unset" {
    mkdir -p "$FAKE/core"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "modules=[%s]\\n" "${CHEZ_MODULES-UNSET}"' >"$FAKE/core/chez.sh"
    # Set-but-empty is the honest answer for a Mac with no modules. Unset sends
    # the dispatcher down its ~200 ms `chezmoi data` fallback on every run, and
    # nothing about that failure is visible except the latency.
    run_zsh "$(extract _chez_run chez); chez help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"modules=[]"* ]] || return 1
}

@test "chez cd never reaches the dispatcher, which cannot change a directory" {
    mkdir -p "$FAKE/core"
    cat >"$FAKE/core/chez.sh" <<'EOF'
#!/usr/bin/env bash
printf 'SHOULD-NOT-DISPATCH
'
EOF
    run_zsh "$(extract _chez_run chez); chez cd"
    [ "$status" -eq 0 ]
    no_match 'SHOULD-NOT-DISPATCH' <<<"$output"
}

# ─── chez bump: routine dependency-bump previewer ────────────────────────────
# Only the untracked-removal PREVIEW is asserted (the interesting, shared logic);
# brew update/upgrade + mise upgrade are stubbed no-ops.

@test "chez bump previews the untracked removal set and points at chez mirror" {
    cat >"$STUBS/cleanup.out" <<'OUT'
Would uninstall formulae:
orphan-cli
Run `brew bundle cleanup --force` to make these changes.
OUT
    BREW_CLEANUP_OUT="$STUBS/cleanup.out" \
        run_bash "$REPO_ROOT/features/brew/bump.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"formula"* ]] || return 1
    [[ "$output" == *"orphan-cli"* ]] || return 1
    [[ "$output" == *"chez mirror"* ]]  # reconcile hint
}

@test "chez bump reports a fully-tracked machine when nothing is untracked" {
    : >"$STUBS/cleanup.out"  # brew bundle cleanup finds nothing to remove
    BREW_CLEANUP_OUT="$STUBS/cleanup.out" \
        run_bash "$REPO_ROOT/features/brew/bump.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"every installed package is tracked"* ]] || return 1
}
