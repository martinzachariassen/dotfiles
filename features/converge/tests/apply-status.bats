#!/usr/bin/env bats
# Behavioural tests for chez apply and chez status — the two converge verbs that
# read and write $HOME. They run the committed scripts against a fake repo with
# git, chezmoi and brew stubbed, so every branch is driven by env var.
#
# These used to sed the function bodies out of dot_zshrc.tmpl and eval them
# under zsh; the bodies are features/converge/{apply,status}.sh now.

setup() {
    load '../../../core/testing/helper'
    ZSHRC="$REPO_ROOT/src/dot_config/zsh/dot_zshrc.tmpl"
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"

    command -v jq >/dev/null 2>&1 || skip "jq not installed (brew_active_files needs it)"

    FAKE="$(mktemp -d)"
    mkdir -p "$FAKE/features/brew/lib" "$FAKE/scripts/bin" "$FAKE/core"
    # The real resolver, so these zsh-side tests exercise the committed lib —
    # _chez_brew_removals sources it out of the repo root it's handed.
    cp "$REPO_ROOT/features/brew/lib/tiers.sh" "$FAKE/features/brew/lib/tiers.sh"
    # tiers.sh refuses to load without core/paths.sh; see its header.
    cp "$REPO_ROOT/core/paths.sh" "$FAKE/core/paths.sh"
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

# ─── chez apply: the smart apply wrapper ─────────────────────────────────────

@test "chez apply applies without prompting when there is no drift" {
    # Empty status ⇒ straight to `chezmoi apply --force`, no confirmation gate.
    CHEZMOI_STATUS="" \
        run_bash "$REPO_ROOT/features/converge/apply.sh"
    [ "$status" -eq 0 ]
    grep -q 'apply --force' "$APPLY_LOG"
}

@test "chez apply surfaces a Brewfile-removal drift notice after applying, including casks" {
    # Notice names chez mirror as the reconcile path; chez apply itself never
    # uninstalls. Regression: the notice must use _chez_brew_removals (brew
    # bundle cleanup), not a `brew leaves`-only check — that older approach
    # missed casks entirely.
    cat >"$STUBS/cleanup.out" <<'OUT'
Would uninstall casks:
discord
Run `brew bundle cleanup --force` to make these changes.
OUT
    CHEZMOI_STATUS="" BREW_CLEANUP_OUT="$STUBS/cleanup.out" \
        run_bash "$REPO_ROOT/features/converge/apply.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no active Brewfile"* ]] || return 1
    [[ "$output" == *"chez mirror"* ]] || return 1
}

@test "chez apply propagates a failing apply's exit code" {
    CHEZMOI_STATUS="" CHEZMOI_APPLY_RC=3 \
        run_bash "$REPO_ROOT/features/converge/apply.sh"
    [ "$status" -eq 3 ]
}

# ─── chez status: read-only file + package drift explainer ──────────────────
# The status codes are two columns (left = local $HOME drift, right = repo →
# $HOME apply). chez status splits them into two labelled sections; these tests
# feed the stub a fixed CHEZMOI_STATUS and assert the plain-language grouping.

@test "chez status reports in-sync and no untracked packages when everything is clean" {
    CHEZMOI_STATUS="" \
        run_bash "$REPO_ROOT/features/converge/status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"in sync"* ]] || return 1
    [[ "$output" != *"Untracked Homebrew"* ]] || return 1
}

@test "chez status flags untracked casks, not just formulae, and points at chez mirror" {
    # Regression: the old chezaudit used `brew leaves`, which is formula-only
    # and silently missed untracked casks. chez status must not repeat that.
    cat >"$STUBS/cleanup.out" <<'OUT'
Would uninstall casks:
obs
Run `brew bundle cleanup --force` to make these changes.
OUT
    CHEZMOI_STATUS="" BREW_CLEANUP_OUT="$STUBS/cleanup.out" \
        run_bash "$REPO_ROOT/features/converge/status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Untracked Homebrew"* ]] || return 1
    [[ "$output" == *"cask"* ]] || return 1
    [[ "$output" == *"obs"* ]] || return 1
    [[ "$output" == *"chez mirror"* ]] || return 1
}

@test "chez status groups repo → \$HOME changes under the apply section with plain verbs" {
    # Right column drives the 'what chez apply would write' list: ' M' → modify,
    # ' A' → add. No local drift (left column blank) ⇒ no drift section.
    CHEZMOI_STATUS=$' M .config/zsh/.zshrc\n A .config/foo/bar' \
        run_bash "$REPO_ROOT/features/converge/status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Repo → \$HOME"* ]] || return 1
    [[ "$output" == *"modify"* ]] || return 1
    [[ "$output" == *".config/zsh/.zshrc"* ]] || return 1
    [[ "$output" == *"add"* ]] || return 1
    [[ "$output" == *".config/foo/bar"* ]] || return 1
    [[ "$output" != *"Local drift"* ]]  # nothing edited locally
}

@test "chez status surfaces local drift and the re-add hint" {
    # 'MM' = edited locally (left col) AND repo differs (right col): it must
    # appear under BOTH sections, and the drift section warns about overwrite.
    CHEZMOI_STATUS=$'MM .config/zsh/.zshrc' \
        run_bash "$REPO_ROOT/features/converge/status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Repo → \$HOME"* ]] || return 1
    [[ "$output" == *"Local drift"* ]] || return 1
    [[ "$output" == *"edited"* ]] || return 1
    [[ "$output" == *"re-add"* ]] || return 1
}

@test "chez status -v hands off to the raw \`chezmoi diff\`" {
    # Verbose (and any path arg) must bypass the summary entirely and shell out
    # to `chezmoi diff` — recorded in DIFF_LOG by the stub.
    CHEZMOI_STATUS=$'MM .config/zsh/.zshrc' \
        run_bash "$REPO_ROOT/features/converge/status.sh" -v
    [ "$status" -eq 0 ]
    [[ "$output" != *"Repo → \$HOME"* ]]  # took the passthrough, not the summary
    grep -q '^diff' "$DIFF_LOG"
}

@test "chez status PATH forwards the path to \`chezmoi diff\`" {
    run_bash "$REPO_ROOT/features/converge/status.sh" ~/.zshrc
    [ "$status" -eq 0 ]
    grep -q 'diff .*\.zshrc' "$DIFF_LOG"
}

@test "chez status --help prints usage without touching chezmoi" {
    run_bash "$REPO_ROOT/features/converge/status.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: chez status"* ]] || return 1
    [ ! -s "$DIFF_LOG" ]  # help path shells out to nothing
}

