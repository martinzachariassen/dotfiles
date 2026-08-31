#!/usr/bin/env bats
# git-email.bats — a blank commit email must be recoverable, and never silent.
#
# From a real fresh install: the wizard's email question was left blank (a
# GitHub noreply address is not something anyone has memorised on install day).
# Three things then went wrong, in order of severity.
#
#   1. `~/.config/git/config` rendered `email = ` with nothing after it. git
#      accepts that and authors every commit as "Martin Zachariassen <>" —
#      unattributable on GitHub, and undoable only by rewriting history.
#   2. promptStringOnce had stored "" as a *real answer*, so plain `chez setup`
#      ("fill in newly-added setup keys only") skipped the key forever. The only
#      way back was `chez setup --reset`, which replays the whole wizard.
#   3. Nothing reported it — not the wizard summary, not the completion screen,
#      not chez doctor.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMPL="$REPO_ROOT/src/.chezmoi.toml.tmpl"
    GITCFG="$REPO_ROOT/src/dot_config/git/config.tmpl"
    SIGNERS="$REPO_ROOT/src/dot_config/git/allowed_signers.tmpl"
    WIZ="$REPO_ROOT/features/setup/cli.sh"
    DOCTOR="$REPO_ROOT/features/sign/doctor.sh"
    COMPLETION="$REPO_ROOT/src/.chezmoiscripts/run_onchange_after_99-completion.sh.tmpl"
    FIX="$(mktemp -d)"
    command -v chezmoi >/dev/null 2>&1 && HAS_CHEZMOI=1 || HAS_CHEZMOI=0
}
teardown() { rm -rf "$FIX"; }

# ─── the rendered git config ──────────────────────────────────────────────────

@test "git refuses to commit rather than author one with an empty address" {
    # useConfigOnly is the whole point: without it git silently invents
    # user@hostname, and with `email = ` it writes "<>".
    grep -q 'useConfigOnly = true' "$GITCFG"
}

@test "the empty-email branch never emits a bare 'email =' line" {
    # The exact bytes that caused "Martin Zachariassen <>".
    ! grep -qE '^\s+email = \{\{ \.email \}\}' "$GITCFG"
}

@test "git config reads email through dig, so a missing key cannot abort an apply" {
    # Setup now omits the key entirely when blank; a bare `.email` would fail the
    # whole apply with "map has no entry for key".
    grep -q 'dig "email" "" \.' "$GITCFG"
    ! grep -q '{{ \.email }}' "$GITCFG"
}

@test "allowed_signers also reads email through dig" {
    grep -q 'dig "email" "" \.' "$SIGNERS"
    ! grep -q '{{ \.email }}' "$SIGNERS"
}

@test "useConfigOnly really does stop git committing" {
    # Pin the behaviour this design leans on, rather than trusting the manpage.
    cat >"$FIX/gitconfig" <<'EOF'
[user]
    name = Test Person
    useConfigOnly = true
EOF
    cd "$FIX"
    git init -q repo && cd repo && echo x >a && git add a
    run env GIT_CONFIG_GLOBAL="$FIX/gitconfig" git commit -m "should not happen"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Please tell me who you are"* ]] || return 1
}

# ─── the config template ──────────────────────────────────────────────────────

@test "a blank email is not persisted as an answer" {
    # This is what makes `chez setup` re-ask instead of skipping the key.
    grep -q '{{- if \$email }}' "$TMPL"
}

@test "the email prompt is re-issued when the stored answer is empty" {
    grep -q '{{- if not \$email -}}' "$TMPL"
    grep -q 'promptString "Email for git commits"' "$TMPL"
}

@test "both email prompts use the identical message" {
    # chezmoi keys --promptString by the prompt text; wizard.sh passes exactly
    # one value for it. A different second message would drop the wizard into
    # chezmoi's raw-mode TUI, which cannot run under `curl | bash`.
    run grep -cF '"Email for git commits"' "$TMPL"
    [ "$output" = "2" ]
}

# stub_config NAME [EMAIL] — a chezmoi config carrying just enough [data] to
# render git/config.tmpl. Self-contained on purpose: an earlier version of these
# two tests rendered against whatever the *running machine* had configured, so
# they passed locally (blank email) and failed in CI (no data at all).
stub_config() {
    local out="$FIX/$1.toml"
    {
        echo '[data]'
        echo '    name        = "Ada L"'
        [ -n "${2:-}" ] && printf '    email       = "%s"\n' "$2"
        echo '    profile     = "personal"'
        echo '    signingMode = "off"'
        echo '    signingKey  = ""'
        echo '    modules     = []'
    } >"$out"
    printf '%s' "$out"
}

render_gitconfig() {
    chezmoi execute-template --config="$1" --source="$REPO_ROOT/src" <"$GITCFG"
}

@test "rendering with no email produces a config git will refuse to use" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    run render_gitconfig "$(stub_config noemail)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"useConfigOnly = true"* ]] || return 1
    # No *active* email line — the bytes that produced "Ada L <>". Comments are
    # stripped first: the explanatory comment quotes "email =" itself.
    local active
    active="$(printf '%s\n' "$output" | grep -vE '^[[:space:]]*#' |
        grep -cE '^[[:space:]]*email[[:space:]]*=' || true)"
    [ "$active" -eq 0 ]
}

@test "rendering with an email produces a normal config and no guard" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    run render_gitconfig "$(stub_config withemail ada@example.com)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"email = ada@example.com"* ]] || return 1
    [[ "$output" != *"useConfigOnly"* ]] || return 1
}

# ─── the wizard ───────────────────────────────────────────────────────────────

@test "the wizard warns at the moment the email is left blank" {
    grep -q 'no email set — git will refuse to commit' "$WIZ"
}

@test "the wizard summary never prints an empty email as an answer" {
    ! grep -qF 'dim "  email    $email"' "$WIZ"
    grep -q 'not set — run' "$WIZ"
}

@test "the wizard points at chez setup, not chez setup --reset" {
    # --reset replays the entire wizard; this one question does not need that.
    grep -A6 'no email set' "$WIZ" | grep -q 'chez setup'
    ! grep -A6 'no email set' "$WIZ" | grep -q 'chez setup --reset'
}

# ─── the reporters ────────────────────────────────────────────────────────────

@test "chez doctor checks the commit author" {
    grep -q 'section "Commit author"' "$DOCTOR"
    grep -q 'user.email' "$DOCTOR"
}

@test "chez doctor fails, not warns, on a missing email" {
    # warn() only bumps the ACTION tally and keeps exit 0; an unattributable
    # commit is a defect, so this has to be red.
    grep -A8 'section "Commit author"' "$DOCTOR" | grep -q 'fail "no git email set'
}

@test "the completion screen offers the fix as a numbered next move" {
    grep -q 'EMAIL="{{ dig "email" "" \. }}"' "$COMPLETION"
    grep -q 'No git email is set' "$COMPLETION"
}

@test "the completion step is skipped once an email exists" {
    grep -B2 'No git email is set' "$COMPLETION" | grep -q 'if \[ -z "\$EMAIL" \]'
}
