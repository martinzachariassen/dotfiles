#!/usr/bin/env bats
# Tests for scripts/bin/bootstrap-auth.sh — the post-install account walkthrough.
#
# The script itself is a long, interactive, network-touching sequence (gh/az/
# gcloud/op sign-ins) that isn't safe to drive from a unit test. Its one piece of
# pure decision logic is has_module — the gate that decides whether to run the
# cloud-auth section at all, based on the selected chezmoi .modules. We extract
# the REAL function and run it against a stubbed chezmoi so a regression in the
# gate (e.g. wrong jq path, or not failing closed when chezmoi is absent) fails.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    BOOT="$REPO_ROOT/scripts/bin/bootstrap-auth.sh"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"

    STUBS="$(mktemp -d)"
    # chezmoi stub: `data` echoes CHEZMOI_DATA (the selected-modules JSON).
    cat >"$STUBS/chezmoi" <<'EOF'
#!/usr/bin/env bash
[ "$1" = data ] && { printf '%s' "${CHEZMOI_DATA:-{\}}"; exit 0; }
exit 0
EOF
    chmod +x "$STUBS/chezmoi"
}

teardown() { [ -n "${STUBS:-}" ] && rm -rf "$STUBS"; }

# Pull the multi-line has_module body out of the script (no template directives).
extract() { sed -n '/^has_module() {/,/^}/p' "$BOOT"; }

@test "has_module is true for a selected module" {
    run env PATH="$STUBS:$PATH" CHEZMOI_DATA='{"modules":["cloudAuth","theme"]}' \
        bash -c "$(extract); has_module cloudAuth"
    [ "$status" -eq 0 ]
}

@test "has_module is false for a module that was not selected" {
    run env PATH="$STUBS:$PATH" CHEZMOI_DATA='{"modules":["theme"]}' \
        bash -c "$(extract); has_module cloudAuth"
    [ "$status" -ne 0 ]
}

@test "has_module is false when the modules list is empty or absent" {
    run env PATH="$STUBS:$PATH" CHEZMOI_DATA='{}' \
        bash -c "$(extract); has_module cloudAuth"
    [ "$status" -ne 0 ]
}

@test "has_module fails closed when chezmoi is not installed" {
    # No chezmoi on PATH ⇒ the walkthrough must NOT assume a module is active.
    # /usr/bin:/bin has bash but not Homebrew's chezmoi; skip if that's not true.
    PATH="/usr/bin:/bin" command -v chezmoi >/dev/null 2>&1 && skip "chezmoi on system PATH"
    run env PATH="/usr/bin:/bin" bash -c "$(extract); has_module cloudAuth"
    [ "$status" -ne 0 ]
}
