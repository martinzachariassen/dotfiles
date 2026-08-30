#!/usr/bin/env bats
# Tests for scripts/bin/chezup.sh — the everyday "converge this Mac to the
# repo" verb (pull → preview drift → apply) behind the `chezup` zsh function.
#
# chezup runs most often, so its control flow must be exactly right across
# every state: missing/renamed repo, failed pull, clean tree, drifted files,
# missing chezmoi, DRY_RUN/YES overrides — none of which `bash -n` can see. We
# run the real script with a fake repo and stubbed git/chezmoi, driving each
# branch by env var.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHEZUP="$REPO_ROOT/scripts/bin/chezup.sh"
    command -v bash >/dev/null 2>&1 || skip "bash not installed"

    REPO="$(mktemp -d)"
    mkdir -p "$REPO/.git"

    STUBS="$(mktemp -d)"
    APPLY_LOG="$STUBS/apply.log"
    STATE="$STUBS/state"  # lets the git stub model a pull that advances HEAD
    mkdir -p "$STATE"

    # git stub: HEAD fixed by default (up-to-date pull). GIT_ADVANCE=1 drops a
    # marker so post-pull rev-parse returns a different hash; GIT_PULL_RC forces
    # a failed pull.
    cat >"$STUBS/git" <<EOF
#!/usr/bin/env bash
args="\$*"
case "\$args" in
    *rev-parse*)
        if [ -f "$STATE/pulled" ]; then echo "\${GIT_AFTER:-fedcba9876543210}"
        else echo "\${GIT_BEFORE:-abcdef1234567890}"; fi ;;
    *rev-list*)  echo "\${GIT_PULLED_COUNT:-0}" ;;
    *pull*)
        [ "\${GIT_ADVANCE:-0}" = 1 ] && : >"$STATE/pulled"
        exit "\${GIT_PULL_RC:-0}" ;;
    *)           exit 0 ;;
esac
EOF

    # chezmoi stub: `status --exclude scripts` prints CHEZMOI_STATUS (file
    # drift), `status --include scripts` prints CHEZMOI_STATUS_SCRIPTS (pending
    # hooks) — chezup asks both, and the two answers drive different branches.
    # apply records args and honours CHEZMOI_APPLY_RC.
    # The module gate reads `chezmoi data`. Default is empty, which the gate
    # treats as "can't resolve, say nothing" — so every pre-existing test below
    # runs exactly as it did before the gate existed.
    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
if [ "\$1" = data ]; then
    printf '%s' "\${CHEZMOI_DATA:-}"
    exit 0
fi
if [ "\$1" = status ]; then
    case "\$*" in
        *--include*scripts*) out="\${CHEZMOI_STATUS_SCRIPTS:-}" ;;
        *)                   out="\${CHEZMOI_STATUS:-}" ;;
    esac
    printf '%s' "\$out"
    [ -n "\$out" ] && echo
    exit 0
fi
if [ "\$1" = apply ]; then
    shift
    printf 'apply %s\n' "\$*" >>"$APPLY_LOG"
    exit "\${CHEZMOI_APPLY_RC:-0}"
fi
exit 0
EOF
    chmod +x "$STUBS/git" "$STUBS/chezmoi"
}

teardown() {
    [ -n "${REPO:-}" ] && rm -rf "$REPO"
    [ -n "${STUBS:-}" ] && rm -rf "$STUBS"
    [ -n "${ISO:-}" ] && rm -rf "$ISO"
    return 0  # never let an unset-ISO short-circuit fail the test
}

# run_chezup — real script under stubbed PATH + a fake repo. Extra env in $1.
run_chezup() {
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" APPLY_LOG="$APPLY_LOG" \
        $1 bash "$CHEZUP"
}

# ─── Missing / broken repo ──────────────────────────────────────────────────

@test "chezup fails when the source dir has no git repo" {
    rm -rf "$REPO/.git"
    run_chezup ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"no git repo"* ]] || return 1
    [ ! -s "$APPLY_LOG" ]  # never reached apply
}

@test "chezup aborts when git pull --ff-only fails" {
    run_chezup "GIT_PULL_RC=1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"git pull --ff-only failed"* ]] || return 1
    [ ! -s "$APPLY_LOG" ]
}

@test "chezup fails when chezmoi is not on PATH" {
    # chezmoi lives in Homebrew's bin (outside /usr/bin:/bin), so this
    # reliably hides it.
    PATH="/usr/bin:/bin" command -v chezmoi >/dev/null 2>&1 && skip "chezmoi on system PATH"
    local nochez="$STUBS/nochez"
    mkdir -p "$nochez"
    ln -s "$STUBS/git" "$nochez/git"
    run env PATH="$nochez:/usr/bin:/bin" DOTFILES_DIR="$REPO" GIT_PULL_RC=0 bash "$CHEZUP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"chezmoi is not on PATH"* ]] || return 1
}

# ─── Clean tree ─────────────────────────────────────────────────────────────

@test "chezup reports in-sync and exits 0 when nothing drifted" {
    run_chezup "CHEZMOI_STATUS= CHEZMOI_STATUS_SCRIPTS="
    [ "$status" -eq 0 ]
    [[ "$output" == *"up to date"* ]] || return 1
    [[ "$output" == *"already in sync"* ]] || return 1
    [ ! -s "$APPLY_LOG" ]  # in sync ⇒ no apply
}

# ─── Pending hooks with no file drift ───────────────────────────────────────
# The recovery case: a partial install (brew bundle died mid-way) leaves every
# managed file correct, so file drift is empty while the run_after hooks are
# still pending. chezup must apply anyway — every hook that fails tells the
# user to re-run chezup, and that advice is only true if this branch applies.
# (Stub values carry no spaces: run_chezup word-splits its env string.)

@test "chezup applies when only hooks are pending (no file drift)" {
    run_chezup "CHEZMOI_STATUS= CHEZMOI_STATUS_SCRIPTS=_R_.chezmoiscripts/02-brew-bundle.sh YES=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no managed files drifted"* ]] || return 1
    [[ "$output" == *"hook(s) pending"* ]] || return 1
    [[ "$output" != *"already in sync"* ]] || return 1
    grep -q 'apply --force' "$APPLY_LOG"
}

@test "chezup counts file drift and pending hooks separately" {
    run_chezup "CHEZMOI_STATUS=M_dot_zshrc CHEZMOI_STATUS_SCRIPTS=_R_.chezmoiscripts/02-brew-bundle.sh YES=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 managed file(s) drifted"* ]] || return 1
    [[ "$output" == *"1 apply hook(s) pending"* ]] || return 1
    grep -q 'apply --force' "$APPLY_LOG"
}

@test "chezup reports how many commits it pulled when the repo advanced" {
    # before != after ⇒ the 'pulled N commit(s)' branch instead of 'up to date'.
    run_chezup "GIT_ADVANCE=1 GIT_PULLED_COUNT=3 CHEZMOI_STATUS= CHEZMOI_STATUS_SCRIPTS="
    [ "$status" -eq 0 ]
    [[ "$output" == *"pulled 3 commit"* ]] || return 1
    [[ "$output" != *"up to date"* ]] || return 1
}

@test "chezup fails loudly (exit 1) when its core/ui.sh helper is missing" {
    ISO="$(mktemp -d)"
    mkdir -p "$ISO/scripts/bin"  # note: no core/ ⇒ ui.sh is absent
    cp "$CHEZUP" "$ISO/scripts/bin/chezup.sh"
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" bash "$ISO/scripts/bin/chezup.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || return 1
    [[ "$output" == *"ui.sh"* ]] || return 1
}

# ─── Drift → apply ──────────────────────────────────────────────────────────

@test "chezup applies drifted files when confirmation is bypassed with YES=1" {
    run_chezup "CHEZMOI_STATUS=MM_dot_zshrc YES=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"drifted"* ]] || return 1
    [[ "$output" == *"chezup complete"* ]] || return 1
    grep -q 'apply --force' "$APPLY_LOG"
}

@test "chezup surfaces a failing apply as exit 1" {
    run_chezup "CHEZMOI_STATUS=M_dot_zshrc YES=1 CHEZMOI_APPLY_RC=1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"apply failed"* ]] || return 1
}

# ─── DRY_RUN: preview only, never mutate ────────────────────────────────────

@test "chezup with DRY_RUN=1 previews the apply without running it" {
    run_chezup "CHEZMOI_STATUS=M_dot_zshrc YES=1 DRY_RUN=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry-run"* ]] || return 1
    # The apply command is printed, not executed — so the stub logged nothing.
    [ ! -s "$APPLY_LOG" ]
}

# ─── New modules since setup ────────────────────────────────────────────────
#
# promptMultichoiceOnce keeps the first answer forever and chezup only applies,
# so a module added to the catalog after a machine was set up is invisible on it
# without this gate. The answer is recorded in `modulesSeen` either way, which is
# what stops a declined module being asked about on every single run.
#
# The prompt itself reads /dev/tty, which bats does not provide; these cover
# every branch around it. The accept/decline writes are covered where they live,
# in tests/modules-lib.bats.

# CATALOG — two modules enabled and seen, one (claudeDistiller) brand new.
setup_catalog() {
    CFG="$STUBS/chezmoi.toml"
    cat >"$CFG" <<'EOF'
sourceDir = "/repo"

[data]
    profile     = "work"
    modules     = ["macApps", "theme"]
    modulesSeen = ["macApps", "theme"]
EOF
    CATALOG='{"modules":["macApps","theme"],"modulesSeen":["macApps","theme"],
        "moduleCatalog":{"macApps":"GUI and AI apps","theme":"Catppuccin Mocha",
        "claudeDistiller":"Nightly distillation of Claude sessions"}}'
}

# The JSON holds spaces, which run_chezup's unquoted-$1 env would split.
run_chezup_data() { # run_chezup_data DATA_JSON EXTRA_ENV
    run env PATH="$STUBS:$PATH" DOTFILES_DIR="$REPO" APPLY_LOG="$APPLY_LOG" \
        CHEZMOI_CONFIG_FILE="$CFG" CHEZMOI_DATA="$1" \
        $2 bash "$CHEZUP"
}

@test "chezup lists a module the catalog gained since this Mac was set up" {
    setup_catalog
    run_chezup_data "$CATALOG" "CHEZMOI_STATUS=M_dot_zshrc YES=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 new module since this Mac was set up"* ]] || return 1
    [[ "$output" == *"claudeDistiller"* ]] || return 1
    # The catalog description, so the choice can be made without reading docs.
    [[ "$output" == *"Nightly distillation of Claude sessions"* ]] || return 1
}

@test "chezup says nothing about modules when the catalog holds nothing new" {
    setup_catalog
    run_chezup_data "$(printf '%s' "$CATALOG" | tr -d '\n' |
        sed 's/"modulesSeen":\["macApps","theme"\]/"modulesSeen":["macApps","theme","claudeDistiller"]/')" \
        "CHEZMOI_STATUS=M_dot_zshrc YES=1"
    [ "$status" -eq 0 ]
    [[ "$output" != *"new module"* ]] || return 1
}

@test "chezup does not re-offer a module that was already declined" {
    # Declined = in modulesSeen, absent from modules. The difference between
    # "never asked" and "asked and said no" is the whole point of the key.
    setup_catalog
    run_chezup_data '{"modules":["macApps"],"modulesSeen":["macApps","claudeDistiller"],
        "moduleCatalog":{"macApps":"GUI","claudeDistiller":"Nightly distillation"}}' \
        "CHEZMOI_STATUS=M_dot_zshrc YES=1"
    [ "$status" -eq 0 ]
    [[ "$output" != *"new module"* ]] || return 1
}

@test "chezup never enables a module unattended under YES=1" {
    # YES=1 means "don't ask before applying", not "decide the config for me".
    setup_catalog
    run_chezup_data "$CATALOG" "CHEZMOI_STATUS=M_dot_zshrc YES=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Not enabling anything unattended"* ]] || return 1
    grep -qF 'modules     = ["macApps", "theme"]' "$CFG"
    grep -qF 'modulesSeen = ["macApps", "theme"]' "$CFG"
    # …and the run still converges; the gate is never a reason to stop.
    grep -q 'apply --force' "$APPLY_LOG"
}

@test "chezup with DRY_RUN=1 does not touch the module list" {
    setup_catalog
    run_chezup_data "$CATALOG" "CHEZMOI_STATUS=M_dot_zshrc YES=1 DRY_RUN=1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claudeDistiller"* ]] || return 1
    [[ "$output" == *"not touching the module list"* ]] || return 1
    grep -qF 'modulesSeen = ["macApps", "theme"]' "$CFG"
}

@test "chezup offers modules before the drift check, so one applies same-run" {
    # Ordering matters: enabling a module renders new files, and those must be
    # counted by the status call that follows — not left for the next chezup.
    setup_catalog
    run_chezup_data "$CATALOG" "CHEZMOI_STATUS=M_dot_zshrc YES=1"
    local at_module at_drift
    at_module="$(printf '%s\n' "$output" | grep -n 'new module' | head -1 | cut -d: -f1)"
    at_drift="$(printf '%s\n' "$output" | grep -n 'drifted' | head -1 | cut -d: -f1)"
    [ -n "$at_module" ] && [ -n "$at_drift" ]
    [ "$at_module" -lt "$at_drift" ]
}

@test "chezup keeps going when chezmoi data cannot be resolved" {
    # No jq, a chezmoi too old to have moduleCatalog, a broken config: the gate
    # has nothing to compare and must stay silent rather than guess.
    setup_catalog
    run_chezup_data "" "CHEZMOI_STATUS=M_dot_zshrc YES=1"
    [ "$status" -eq 0 ]
    [[ "$output" != *"new module"* ]] || return 1
    grep -q 'apply --force' "$APPLY_LOG"
}
