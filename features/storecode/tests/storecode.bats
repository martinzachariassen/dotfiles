#!/usr/bin/env bats
# storecode: the work-only exception.
#
# It is installed by its own hook from an installer set in data — never from a
# Brewfile — and ~/.storecode is permanently on chezclean's keepHome list. Both
# halves of that contract are pinned here, along with the hook's guards, the
# render-time values the template threads into the engine, and the engine's own
# behaviour.

setup() {
    load '../../../core/testing/helper'
    SRC_DIR="$REPO_ROOT/src"
    STORECODE_DATA="$SRC_DIR/.chezmoidata/storecode.toml"
    STORECODE_HOOK="$SRC_DIR/.chezmoiscripts/run_onchange_after_05-storecode.sh.tmpl"
    HOOK_SH="$REPO_ROOT/features/storecode/hook.sh"
}

# Run the engine against a scratch HOME with no real `storecode` on PATH, so the
# install decision is driven by the arguments rather than by the host.
run_hook() { # $1 = fake HOME, $2 = install command
    run env PATH="/usr/bin:/bin" bash "$HOOK_SH" "$1" "${2-}"
}

# ─── storecode exemption ────────────────────────────────────────────────────

@test "storecode is exempt: ~/.storecode is on keepHome, never a Brewfile package" {
    skip_unless chezmoi
    chezmoi_stub_config
    local keephome
    keephome="$(chezmoi_render_str '{{ range .cleanup.keepHome }}{{ . }}{{ "\n" }}{{ end }}')"
    grep -qxF ".storecode" <<<"$keephome"
    # The Brewfiles live with the brew feature; pointing this at the old
    # packages/ path would make it pass by scanning an empty directory.
    [ -f "$REPO_ROOT/features/brew/Brewfile" ]
    no_match '(brew|cask)[[:space:]]+"[^"]*storecode' "$REPO_ROOT"/features/brew/Brewfile*
}

# ─── the hook template: render-time decisions only ───────────────────────────

@test "the storecode install hook is work-profile + darwin gated" {
    grep -qF '{{ if ne .chezmoi.os "darwin" -}}' "$STORECODE_HOOK"
    grep -qF '{{ if ne .profile "work" -}}' "$STORECODE_HOOK"
    grep -qF '.storecode.installCmd' "$STORECODE_HOOK"
    grep -qE '^\[storecode\]' "$STORECODE_DATA"
}

@test "the hook threads home and the configured installer into the engine" {
    skip_unless chezmoi
    chezmoi_stub_config 'storecode = { installCmd = "curl -fsSL https://example.invalid/i.sh | bash" }'
    # The exec line sits outside both template guards, so it renders on any
    # profile — which is what lets this run unchanged on Linux CI.
    local exec_line
    exec_line="$(chezmoi_render_file "$STORECODE_HOOK" "$BATS_TEST_TMPDIR/rhome" | sed -n '/^exec /,$p' | tr '\n' ' ')"
    [[ "$exec_line" == *"features/storecode/hook.sh"* ]] || return 1
    [[ "$exec_line" == *"$BATS_TEST_TMPDIR/rhome"* ]] || return 1
    [[ "$exec_line" == *"https://example.invalid/i.sh"* ]] || return 1
}

# ─── the engine ──────────────────────────────────────────────────────────────

@test "the engine is idempotent: skips when ~/.storecode already exists" {
    local fakehome="$BATS_TEST_TMPDIR/schome-present"
    mkdir -p "$fakehome/.storecode" # the "already installed" marker
    run_hook "$fakehome" "echo RAN" # would show up below if it ever ran
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]] || return 1
    [[ "$output" != *RAN* ]] || return 1
}

@test "the engine with no installer configured prints guidance and exits 0 (never fails an apply)" {
    grep -qE '^installCmd = ""' "$STORECODE_DATA" # the committed default
    local fakehome="$BATS_TEST_TMPDIR/schome-absent"
    mkdir -p "$fakehome"
    run_hook "$fakehome" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"no installer is configured yet"* ]] || return 1
    [[ "$output" != *"already installed"* ]] || return 1
}

@test "the engine runs the configured installer when one is set" {
    local fakehome="$BATS_TEST_TMPDIR/schome-install"
    mkdir -p "$fakehome"
    run_hook "$fakehome" "echo RAN-INSTALLER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RAN-INSTALLER"* ]] || return 1
    [[ "$output" == *"storecode installed"* ]] || return 1
}

@test "a failing installer is reported with the command to retry by hand" {
    local fakehome="$BATS_TEST_TMPDIR/schome-fail"
    mkdir -p "$fakehome"
    # A subshell, not a bare `exit`: the engine runs the installer through
    # `eval`, so `exit 3` would end the engine itself and never reach the
    # failure branch this is here to pin.
    run_hook "$fakehome" "sh -c 'exit 3'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"storecode install failed"* ]] || return 1
    [[ "$output" == *"sh -c 'exit 3'"* ]] || return 1
}
