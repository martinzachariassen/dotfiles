#!/usr/bin/env bats
# storecode: the work-only exception.
#
# It is installed by its own hook from an installer set in data — never from a
# Brewfile — and ~/.storecode is permanently on chezclean's keepHome list. Both
# halves of that contract are pinned here, along with the hook's guards and its
# never-fail-an-apply behaviour.

setup() {
    load '../../../core/testing/helper'
    SRC_DIR="$REPO_ROOT/src"
    CLEAN_DATA="$SRC_DIR/.chezmoidata/clean.toml"
    STORECODE_DATA="$SRC_DIR/.chezmoidata/storecode.toml"
    STORECODE_HOOK="$SRC_DIR/.chezmoiscripts/run_onchange_after_05-storecode.sh.tmpl"
    skip_unless chezmoi
    chezmoi_stub_config
}

# The hook's logic BELOW the darwin/work template guards — the `home=` line
# onward — so the behavioural tests run identically on macOS and on Linux CI,
# where the darwin guard would otherwise short-circuit.
_render_storecode_body() { # $1 = fake HOME
    chezmoi_render_file "$STORECODE_HOOK" "$1" | sed -n '/^home=/,$p'
}

# ─── storecode exemption ────────────────────────────────────────────────────

@test "storecode is exempt: ~/.storecode is on keepHome, never a Brewfile package" {
    chezmoi_stub_config
    local keephome
    keephome="$(chezmoi_render_str '{{ range .cleanup.keepHome }}{{ . }}{{ "\n" }}{{ end }}')"
    grep -qxF ".storecode" <<<"$keephome"
    ! grep -rqiE '(brew|cask)[[:space:]]+"[^"]*storecode' "$REPO_ROOT/packages/"
}

# ─── 05-storecode install hook ───────────────────────────────────────────────

@test "the storecode install hook is work-profile + darwin gated" {
    grep -qF '{{ if ne .chezmoi.os "darwin" -}}' "$STORECODE_HOOK"
    grep -qF '{{ if ne .profile "work" -}}' "$STORECODE_HOOK"
    grep -qF '.storecode.installCmd' "$STORECODE_HOOK"
    grep -qE '^\[storecode\]' "$STORECODE_DATA"
}

@test "05-storecode is idempotent: skips when ~/.storecode already exists" {
    chezmoi_stub_config
    local fakehome="$BATS_TEST_TMPDIR/schome-present"
    mkdir -p "$fakehome/.storecode" # the "already installed" marker
    local body
    body="$(_render_storecode_body "$fakehome")"
    # PATH has no real `storecode`, so the skip is driven by the dir, not the host.
    run env PATH="/usr/bin:/bin" bash -c "$body"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]] || return 1
}

@test "05-storecode with no installer configured prints guidance and exits 0 (never fails an apply)" {
    chezmoi_stub_config
    grep -qE '^installCmd = ""' "$STORECODE_DATA"
    local fakehome="$BATS_TEST_TMPDIR/schome-absent"
    mkdir -p "$fakehome" # no ~/.storecode, and storecode not on the stub PATH
    local body
    body="$(_render_storecode_body "$fakehome")"
    run env PATH="/usr/bin:/bin" bash -c "$body"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no installer is configured yet"* ]] || return 1
    [[ "$output" != *"already installed"* ]] || return 1
}
