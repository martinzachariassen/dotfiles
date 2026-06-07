#!/usr/bin/env bats
# Static + dynamic checks for .chezmoiscripts/*.sh.tmpl.
#
# Why this exists:
#   The chezmoi-managed scripts run on every `chezmoi apply`, but the existing
#   CI only checks bash syntax of the rendered bodies (render-check.sh runs
#   `bash -n`). That catches parse errors but not runtime regressions like:
#     - a missing darwin-only guard letting `brew` calls fire on Linux,
#     - a script naming that breaks chezmoi's run-order,
#     - a missing `set -uo pipefail` so an unset var doesn't surface,
#     - a missing bash shebang.
#
#   The dynamic check renders each template with stub chezmoi data and
#   executes it on the (Linux) bats runner under a stripped PATH. Every
#   macOS-targeting script must exit 0 via its `{{ if ne .chezmoi.os "darwin"
#   }}exit 0{{ end }}` guard; the OS-agnostic 99-completion summary must run
#   to completion. On macOS, the dynamic test is skipped — the same scripts
#   would actually call brew/sudo and aren't safe to drive from a unit test.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPTS_DIR="$REPO_ROOT/.chezmoiscripts"

    HAS_CHEZMOI=0
    command -v chezmoi >/dev/null 2>&1 && HAS_CHEZMOI=1
}

# ─── Static: every script meets the basic shape ────────────────────────────

@test "every chezmoi script has a bash shebang" {
    for tmpl in "$SCRIPTS_DIR"/*.sh.tmpl; do
        first_line="$(head -1 "$tmpl")"
        case "$first_line" in
            '#!/usr/bin/env bash'|'#!/bin/bash') ;;
            *)
                echo "missing bash shebang in $(basename "$tmpl"):"
                echo "    $first_line"
                return 1
                ;;
        esac
    done
}

@test "every chezmoi script enables strict bash mode" {
    # `set -uo pipefail` (no -e) is acceptable when the script wants to
    # continue past failing commands (e.g. brew-bundle's continue-on-error).
    # `set -euo pipefail` is the stricter default.
    for tmpl in "$SCRIPTS_DIR"/*.sh.tmpl; do
        if ! grep -qE '^set -e?uo pipefail$' "$tmpl"; then
            echo "missing 'set -[e]uo pipefail' in $(basename "$tmpl")"
            return 1
        fi
    done
}

@test "every chezmoi script follows the run_<when>_<seq>-<name>.sh.tmpl naming" {
    # chezmoi uses the prefix to choose when the script runs; a typo here
    # silently demotes the script to "every-apply" or vice-versa.
    for tmpl in "$SCRIPTS_DIR"/*.sh.tmpl; do
        name="$(basename "$tmpl")"
        case "$name" in
            run_before_[0-9][0-9]*-*.sh.tmpl) ;;
            run_after_[0-9][0-9]*-*.sh.tmpl) ;;
            run_once_before_[0-9][0-9]*-*.sh.tmpl) ;;
            run_onchange_after_[0-9][0-9]*-*.sh.tmpl) ;;
            *)
                echo "non-conforming chezmoi script name: $name"
                echo "expected one of: run_before_NN-, run_after_NN-, run_once_before_NN-, run_onchange_after_NN-"
                return 1
                ;;
        esac
    done
}

@test "macOS-targeting chezmoi scripts include the darwin guard" {
    # Skipped by name: 99-completion is OS-agnostic by design (it just prints
    # a closing banner with chezmoi-rendered data). If you add another
    # OS-agnostic script, add it here.
    for tmpl in "$SCRIPTS_DIR"/*.sh.tmpl; do
        case "$(basename "$tmpl")" in
            run_onchange_after_99-completion.sh.tmpl) continue ;;
        esac
        if ! grep -qF '{{ if ne .chezmoi.os "darwin" -}}' "$tmpl"; then
            echo "missing darwin guard in $(basename "$tmpl"):"
            echo "    expected '{{ if ne .chezmoi.os \"darwin\" -}}' near the top"
            return 1
        fi
    done
}

# ─── Dynamic: rendered bodies behave on Linux ──────────────────────────────

_setup_stub_chezmoi() {
    STUB_DIR="$BATS_TEST_TMPDIR/chezmoi-stub"
    mkdir -p "$STUB_DIR/home/.config/chezmoi" "$STUB_DIR/dst"
    cat > "$STUB_DIR/home/.config/chezmoi/chezmoi.toml" <<EOF
sourceDir = "$REPO_ROOT"

[data]
    name           = "CI"
    email          = "ci@example.com"
    signingKey     = "ssh-ed25519 AAAAci-placeholder"
    profile        = "personal"
    useOnePassword = true

    [data.features]
        macApps   = true
EOF
}

_render_template() {
    local tmpl="$1"
    HOME="$STUB_DIR/home" XDG_CONFIG_HOME="$STUB_DIR/home/.config" \
        chezmoi execute-template \
            --config="$STUB_DIR/home/.config/chezmoi/chezmoi.toml" \
            --source="$REPO_ROOT" \
            --destination="$STUB_DIR/dst" \
            --file "$tmpl"
}

@test "each rendered chezmoi script exits 0 on Linux" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    [ "$(uname -s)" = "Darwin" ] && skip "macOS scripts would actually call brew/sudo here; this test is the Linux regression guard"

    _setup_stub_chezmoi

    for tmpl in "$SCRIPTS_DIR"/*.sh.tmpl; do
        local rendered_file="$STUB_DIR/$(basename "$tmpl" .tmpl).rendered"
        if ! _render_template "$tmpl" > "$rendered_file" 2>&1; then
            echo "render failed: $(basename "$tmpl")"
            cat "$rendered_file"
            return 1
        fi

        # Stripped PATH ensures a missing guard would crash on the first
        # macOS-only command (no `brew`, `mise`, `code`, or `defaults` here).
        # HOME is the isolated stub so any rogue `rm -rf` only nukes scratch.
        run env -i \
            HOME="$STUB_DIR/home" \
            PATH="/usr/bin:/bin" \
            LANG="C.UTF-8" \
            bash "$rendered_file"
        if [ "$status" -ne 0 ]; then
            echo "rendered script failed: $(basename "$tmpl")"
            echo "exit=$status"
            echo "---rendered---"
            head -40 "$rendered_file"
            echo "---output---"
            printf '%s\n' "$output" | tail -20
            return 1
        fi
    done
}
