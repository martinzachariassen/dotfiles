#!/usr/bin/env bats
# appleDev module: the Swift/iOS tooling must be gated coherently — the two
# committed config files, the VS Code [swift] settings, and the extension mirror
# all appear iff appleDev is selected, and vanish cleanly when it isn't.
#
# Why this exists:
#   Module gating spans four files that have to agree (.chezmoiignore, the
#   settings template, the 03-vscode hook, and the Brewfile). A drift in any one
#   ships half a feature. Two failure modes are pinned here specifically:
#     1. Ignoring .config/swiftlint/config.yml (the file) but not the directory
#        leaves an empty ~/.config/swiftlint on every non-appleDev machine.
#     2. A stray comma in the gated [swift] block renders invalid JSON only when
#        the module is on — something render-check (bash/zsh only) never catches.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SRC_DIR="$REPO_ROOT/src"
    SETTINGS="$SRC_DIR/Library/Application Support/Code/User/settings.json.tmpl"
    VSCODE_HOOK="$SRC_DIR/.chezmoiscripts/run_onchange_after_03-vscode.sh.tmpl"

    HAS_CHEZMOI=0
    command -v chezmoi >/dev/null 2>&1 && HAS_CHEZMOI=1
}

# Write a chezmoi config whose only variable is the selected-modules list, so
# each test renders the source tree exactly as a machine with that module set
# would. $1 is a TOML array literal, e.g. '["macApps","appleDev"]'.
_stub_config() {
    STUB="$BATS_TEST_TMPDIR/home"
    mkdir -p "$STUB/.config/chezmoi" "$BATS_TEST_TMPDIR/dst"
    cat > "$STUB/.config/chezmoi/chezmoi.toml" <<EOF
sourceDir = "$SRC_DIR"

[data]
    name           = "CI"
    email          = "ci@example.com"
    modules        = $1
    signingKey     = "ssh-ed25519 AAAAplaceholder"
    profile        = "personal"
    useOnePassword = false

    [data.features]
        macApps = true
EOF
}

_managed() {
    HOME="$STUB" XDG_CONFIG_HOME="$STUB/.config" \
        chezmoi managed \
            --config="$STUB/.config/chezmoi/chezmoi.toml" \
            --source="$SRC_DIR" \
            --destination="$BATS_TEST_TMPDIR/dst"
}

_render() {
    HOME="$STUB" XDG_CONFIG_HOME="$STUB/.config" \
        chezmoi execute-template \
            --config="$STUB/.config/chezmoi/chezmoi.toml" \
            --source="$SRC_DIR" \
            --destination="$BATS_TEST_TMPDIR/dst" \
            --file "$1"
}

# Fail unless the file at $1 is valid JSONC (VS Code dialect: // and /* */
# comments plus trailing commas). Mirrors scripts/ci/lint-config.sh's validator,
# but for the rendered template — which no other check parses.
_assert_valid_jsonc() {
    python3 - "$1" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    s = fh.read()

def strip(s):
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\" and j + 1 < n:
                    j += 2; continue
                if s[j] == '"':
                    j += 1; break
                j += 1
            out.append(s[i:j]); i = j
        elif c == "/" and i + 1 < n and s[i + 1] == "/":
            j = s.find("\n", i); i = n if j == -1 else j
        elif c == "/" and i + 1 < n and s[i + 1] == "*":
            j = s.find("*/", i + 2); i = n if j == -1 else j + 2
        else:
            out.append(c); i += 1
    return "".join(out)

src = re.sub(r",(\s*[\]}])", r"\1", strip(s))
json.loads(src)
PY
}

# ─── .chezmoiignore gating (the empty-dir regression) ───────────────────────────

@test "appleDev on: ~/.swiftformat and the swiftlint config are deployed" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _stub_config '["macApps","appleDev"]'
    run _managed
    [ "$status" -eq 0 ]
    echo "$output" | grep -qx ".swiftformat"
    echo "$output" | grep -qx ".config/swiftlint/config.yml"
}

@test "appleDev off: no swift config AND no empty .config/swiftlint dir" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _stub_config '["macApps"]'
    run _managed
    [ "$status" -eq 0 ]
    # Not just the files — the directory must be unmanaged too, else chezmoi
    # creates an empty ~/.config/swiftlint on machines that never wanted it.
    ! echo "$output" | grep -q "swiftformat"
    ! echo "$output" | grep -q "swiftlint"
}

# ─── VS Code [swift] settings block ─────────────────────────────────────────────

@test "appleDev on: [swift] block present and settings render as valid JSONC" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _stub_config '["macApps","appleDev"]'
    run _render "$SETTINGS"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"\[swift\]"'
    printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/rendered.jsonc"
    _assert_valid_jsonc "$BATS_TEST_TMPDIR/rendered.jsonc"
}

@test "appleDev off: no [swift] block and settings still render as valid JSONC" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _stub_config '["macApps"]'
    run _render "$SETTINGS"
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q '"\[swift\]"'
    printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/rendered.jsonc"
    _assert_valid_jsonc "$BATS_TEST_TMPDIR/rendered.jsonc"
}

# ─── 03-vscode extension mirror gating ──────────────────────────────────────────

@test "appleDev off: the hook excludes the Swift extensions from install/prune" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _stub_config '["macApps"]'
    run _render "$VSCODE_HOOK"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE 'EXCLUDES\+=\(.*swiftlang\.swift-vscode'
    echo "$output" | grep -qE 'EXCLUDES\+=\(.*sweetpad\.sweetpad'
}

@test "appleDev on: the hook does not exclude the Swift extensions" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _stub_config '["macApps","appleDev"]'
    run _render "$VSCODE_HOOK"
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -qE 'EXCLUDES\+=\(.*swiftlang\.swift-vscode'
}

# ─── SwiftFormat / SwiftLint coordination invariant ─────────────────────────────
# Line length is the one rule both tools must agree on (SwiftLint only warns;
# SwiftFormat is what actually wraps). If these drift apart the linter flags what
# the formatter won't fix — the exact trap the shared 120 was chosen to avoid.

@test "swiftformat --maxwidth and swiftlint line_length are both 120" {
    grep -qE '^--maxwidth[[:space:]]+120\b' "$SRC_DIR/dot_swiftformat"
    grep -qE '^[[:space:]]*warning:[[:space:]]*120\b' "$SRC_DIR/exact_dot_config/swiftlint/config.yml"
}
