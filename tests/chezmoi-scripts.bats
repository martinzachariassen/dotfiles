#!/usr/bin/env bats
# Static + dynamic checks for .chezmoiscripts/*.sh.tmpl.
#
# CI's render-check.sh only runs `bash -n` on rendered bodies — catches parse
# errors, not a missing darwin guard, wrong run-order naming, missing
# `set -uo pipefail`, or a missing shebang.
#
# The dynamic check renders each template with stub chezmoi data and executes
# it on the (Linux) bats runner under a stripped PATH: every macOS-targeting
# script must exit 0 via its darwin guard. Skipped on macOS — the same
# scripts would actually call brew/sudo there.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # chezmoi's effective source is the src/ subdir, named by /.chezmoiroot.
    SRC_DIR="$REPO_ROOT/src"
    SCRIPTS_DIR="$SRC_DIR/.chezmoiscripts"

    HAS_CHEZMOI=0
    command -v chezmoi >/dev/null 2>&1 && HAS_CHEZMOI=1
}

# ─── .chezmoiroot: the split that keeps the repo root clean ─────────────────

@test ".chezmoiroot names the src/ source subdir" {
    # If missing/renamed, chezmoi treats the repo root as source and tries to
    # deploy scripts/, packages/, tests/… to $HOME.
    [ -f "$REPO_ROOT/.chezmoiroot" ]
    [ "$(tr -d '[:space:]' <"$REPO_ROOT/.chezmoiroot")" = "src" ]
    [ -d "$SCRIPTS_DIR" ]
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
    # `set -uo pipefail` (no -e) is fine when a script wants to continue past
    # failing commands; `set -euo pipefail` is the stricter default.
    for tmpl in "$SCRIPTS_DIR"/*.sh.tmpl; do
        if ! grep -qE '^set -e?uo pipefail$' "$tmpl"; then
            echo "missing 'set -[e]uo pipefail' in $(basename "$tmpl")"
            return 1
        fi
    done
}

@test "every chezmoi script follows the run_<when>_<seq>-<name>.sh.tmpl naming" {
    # A typo silently demotes the script to "every-apply" or vice-versa.
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
    # 99-completion is OS-agnostic by design; add other exceptions here.
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
sourceDir = "$SRC_DIR"

[data]
    name           = "CI"
    email          = "ci@example.com"
    signingKey     = "ssh-ed25519 AAAAplaceholder"
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
            --source="$SRC_DIR" \
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

        # Stripped PATH: a missing guard would crash on the first macOS-only
        # command. HOME is the isolated stub so a rogue `rm -rf` only hits scratch.
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

# ─── run_onchange hooks must be able to recover from a partial install ──────
# chezmoi records a run_onchange script as done on ANY zero exit — including the
# "tool isn't installed yet, skipping" path. Keyed only on a static manifest
# hash, such a hook would never re-fire, so one failed brew bundle would leave a
# machine permanently without git hooks or VS Code extensions. Each hook that
# skips on a missing tool must fold that tool's presence into its own hash.

@test "hooks that skip on a missing tool key their hash on the tool's presence" {
    # hook → the command whose absence makes it skip
    for pair in \
        "run_onchange_after_02e-pre-commit-install.sh.tmpl:pre-commit" \
        "run_onchange_after_03-vscode.sh.tmpl:code"; do
        tmpl="$SCRIPTS_DIR/${pair%%:*}"
        cmd="${pair##*:}"
        [ -f "$tmpl" ] || { echo "missing hook: $tmpl"; return 1; }
        grep -qF "lookPath \"$cmd\"" "$tmpl" || {
            echo "$(basename "$tmpl") skips when '$cmd' is absent but does not"
            echo "include {{ lookPath \"$cmd\" }} in its hash — it can never re-fire."
            return 1
        }
    done
}

@test "the presence marker flips between absent and present" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    # A marker that renders the same either way would not change the hash.
    run chezmoi execute-template '{{ if lookPath "definitely-not-a-real-tool" }}present{{ else }}absent{{ end }}'
    [ "$status" -eq 0 ]
    [ "$output" = "absent" ]
    run chezmoi execute-template '{{ if lookPath "sh" }}present{{ else }}absent{{ end }}'
    [ "$status" -eq 0 ]
    [ "$output" = "present" ]
}

# ─── Nothing may abort the apply before the completion summary ──────────────
# 99-completion prints the "Next moves" block (chezsign, bootstrap-auth,
# chezdoctor) that a fresh Mac depends on. A hook that exits non-zero takes
# chezmoi's whole apply down with it and the user never sees those steps.

@test "the macOS-defaults hook cannot abort the apply" {
    tmpl="$SCRIPTS_DIR/run_onchange_after_04-macos-defaults.sh.tmpl"
    # set -e is on, so the invocation must be inside a condition, not bare.
    # Matched on the invocation's shape rather than the script's name, so moving
    # the script between directories cannot quietly disarm this.
    grep -qE 'if .*(macos-defaults\.sh|features/macos/cli\.sh)"?; then' "$tmpl" || {
        echo "the defaults script is invoked bare under set -e — a failed pass"
        echo "would abort the apply and skip 05-storecode and 99-completion."
        return 1
    }
    grep -qF 'did not complete' "$tmpl"
}

# ─── A thinned hook must hash the engine it delegates to ────────────────────
# A run_onchange_ hook re-fires when its *rendered body* changes. Move the body
# into a feature and the template stops changing, so chezmoi keeps matching the
# hash it recorded and the hook silently never runs again — no error, no output,
# and the feature quietly stops converging. Every hook that delegates must
# therefore include the file it delegates to.

@test "every hook that delegates to a feature also hashes that file" {
    local tmpl rel
    for tmpl in "$SCRIPTS_DIR"/run_*.sh.tmpl; do
        # Delegation means *executing* a file: the hook has handed its work to
        # that engine, so the engine's content must be part of the hash or the
        # hook silently freezes. Two things deliberately do not count.
        #
        # Sourcing a helper. Hooks 00 and 02 source core/tty.sh and core/sudo.sh
        # and hash neither, and hook 99 sources features/xcode/probe.sh only to
        # decide which next-step line to print. A stale suggestion costs nothing,
        # and re-firing the whole completion summary on every probe edit is noise.
        #
        # Naming a path in output. Hook 99 prints features/auth/cli.sh as an
        # instruction for the user to run later.
        grep -oE '(exec +)?(bash|sh) +"[^"]*features/[a-z]+/[a-z-]+\.sh' "$tmpl" |
            grep -oE 'features/[a-z]+/[a-z-]+\.sh' | sort -u | while IFS= read -r rel; do
            grep -qF "include \"../$rel\"" "$tmpl" || printf '%s -> %s\n' "$(basename "$tmpl")" "$rel"
        done
    done > "$BATS_TEST_TMPDIR/missing"
    if [ -s "$BATS_TEST_TMPDIR/missing" ]; then
        printf 'hook delegates to a file it does not hash (it will stop re-firing):\n' >&2
        sed 's/^/  /' "$BATS_TEST_TMPDIR/missing" >&2
    fi
    [ ! -s "$BATS_TEST_TMPDIR/missing" ]
}

@test "the vscode hook hashes both its engine and its manifest" {
    tmpl="$SCRIPTS_DIR/run_onchange_after_03-vscode.sh.tmpl"
    grep -qF 'include "../features/vscode/hook.sh"' "$tmpl"
    grep -qF 'include "../features/vscode/extensions.txt"' "$tmpl"
}
