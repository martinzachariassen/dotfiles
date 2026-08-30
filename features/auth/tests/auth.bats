#!/usr/bin/env bats
# Tests for has_module, the only pure logic in bootstrap-auth.sh's otherwise
# interactive, network-touching script. Extracts the real function and runs it
# against a stubbed chezmoi.

setup() {
    load '../../../core/testing/helper'
    BOOT="$REPO_ROOT/features/auth/cli.sh"
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
# has_module calls cm_has_module/cm_data_json, so chezmoi-data.sh must be sourced too.
extract() {
    printf '. "%s/core/chezmoi-data.sh"; ' "$REPO_ROOT"
    sed -n '/^has_module() {/,/^}/p' "$BOOT"
}

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
    # /usr/bin:/bin has bash but not Homebrew's chezmoi; skip if that's not true.
    PATH="/usr/bin:/bin" command -v chezmoi >/dev/null 2>&1 && skip "chezmoi on system PATH"
    run env PATH="/usr/bin:/bin" bash -c "$(extract); has_module cloudAuth"
    [ "$status" -ne 0 ]
}
