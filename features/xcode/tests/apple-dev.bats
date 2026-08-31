#!/usr/bin/env bats
# appleDev module: the Swift/iOS tooling must be gated coherently — the two
# committed config files, the VS Code [swift] settings, and the extension mirror
# all appear iff appleDev is selected, and vanish cleanly when it isn't.
#
# Module gating spans four files that must agree (.chezmoiignore, the settings
# template, the 03-vscode hook, the Brewfile); a drift in one ships half a
# feature. Two failure modes pinned specifically: (1) ignoring the swiftlint
# config file but not its directory leaves an empty ~/.config/swiftlint
# everywhere; (2) a stray comma in the gated [swift] block renders invalid
# JSON only when the module is on — render-check (bash/zsh only) never catches it.

setup() {
    load '../../../core/testing/helper'
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

# Negative assertions must go through this. A bare `! grep …` in the middle of
# a test body is exempt from set -e (POSIX: "the return value is being inverted
# with !"), so bats never sees it fail — the assertion silently passes no matter
# what the output contains.
#
# no_match_in <text> <extended-regex>
no_match_in() {
    if grep -qE "$2" <<<"$1"; then
        echo "unexpected match for: $2"
        return 1
    fi
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
    # The directory must be unmanaged too, else chezmoi creates an empty one.
    no_match_in "$output" "swiftformat"
    no_match_in "$output" "swiftlint"
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
    no_match_in "$output" '"\[swift\]"'
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
    no_match_in "$output" 'EXCLUDES\+=\(.*swiftlang\.swift-vscode'
}

# ─── SwiftFormat / SwiftLint coordination invariant ─────────────────────────────
# SwiftLint only warns on line length; SwiftFormat is what actually wraps. If
# these drift apart the linter flags what the formatter won't fix.

@test "swiftformat --maxwidth and swiftlint line_length are both 120" {
    grep -qE '^--maxwidth[[:space:]]+120\b' "$SRC_DIR/dot_swiftformat"
    grep -qE '^[[:space:]]*warning:[[:space:]]*120\b' "$SRC_DIR/dot_config/swiftlint/config.yml"
}

# ─── chez xcode wiring ───────────────────────────────────────────────────────────
# The Xcode layer is the one thing an apply can't install (Apple ID + 2FA, ~40 GB),
# so it ships as a verb the setup points at. Three surfaces have to agree with the
# module gate, or a machine either loses the verb it needs or grows one it can't use.

@test "the table routes chez xcode at this feature, gated on appleDev" {
    # shellcheck source=../../../core/verbs.sh
    . "$REPO_ROOT/core/verbs.sh"
    [ "$(verbs_path xcode)" = "features/xcode/cli.sh" ]
    [ "$(verbs_module xcode)" = "appleDev" ]
    # The gate lives in the table, not in the zshrc: the dispatcher reads it at
    # run time, so the rendered shell config carries no xcode-specific line at
    # all any more — with the module on or off.
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _stub_config '["macApps","appleDev"]'
    run _render "$SRC_DIR/dot_config/zsh/dot_zshrc.tmpl"
    [ "$status" -eq 0 ]
    no_match_in "$output" 'chezxcode'
}

@test "appleDev on: chez help lists the verb; off, it says which module is missing" {
    run env CHEZ_MODULES="appleDev" bash "$REPO_ROOT/core/chez.sh" help
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^    chez xcode +Install Xcode'
    # Gated off, the verb must explain itself rather than read as a typo.
    run env CHEZ_MODULES="" bash "$REPO_ROOT/core/chez.sh" xcode --check
    [ "$status" -eq 1 ]
    echo "$output" | grep -qF 'needs the `appleDev` module'
}

@test "appleDev off: the zshrc has no chez xcode at all" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _stub_config '["macApps"]'
    run _render "$SRC_DIR/dot_config/zsh/dot_zshrc.tmpl"
    [ "$status" -eq 0 ]
    no_match_in "$output" 'chez xcode'
}

@test "the rendered zshrc stays valid zsh with appleDev on" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    _stub_config '["macApps","appleDev"]'
    _render "$SRC_DIR/dot_config/zsh/dot_zshrc.tmpl" > "$BATS_TEST_TMPDIR/zshrc"
    run zsh -n "$BATS_TEST_TMPDIR/zshrc"
    [ "$status" -eq 0 ]
}

@test "appleDev on: the completion hook probes Xcode readiness" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _stub_config '["macApps","appleDev"]'
    run _render "$SRC_DIR/.chezmoiscripts/run_onchange_after_99-completion.sh.tmpl"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF 'features/xcode/probe.sh'
    echo "$output" | grep -qF 'chez xcode'
}

@test "appleDev off: the completion hook never mentions Xcode" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _stub_config '["macApps"]'
    run _render "$SRC_DIR/.chezmoiscripts/run_onchange_after_99-completion.sh.tmpl"
    [ "$status" -eq 0 ]
    no_match_in "$output" 'chez xcode'
    no_match_in "$output" 'xcode\.sh'
}

# The hook counts step numbers rather than hardcoding them, so the two optional
# steps must not collide when both apply — a duplicated "4." in the closing
# summary is the visible symptom.
@test "completion hook: chez sign and chez xcode get distinct step numbers" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _stub_config '["macApps","appleDev"]'
    _render "$SRC_DIR/.chezmoiscripts/run_onchange_after_99-completion.sh.tmpl" \
        > "$BATS_TEST_TMPDIR/completion.sh"
    # Force both optional steps on regardless of this machine's real state: stub
    # the Xcode probes to report "no Xcode", turn signing on and blank its key.
    # (_stub_config sets useOnePassword=false, so signing renders as "off".)
    cat > "$BATS_TEST_TMPDIR/fake-xcode-lib.sh" <<'EOF'
xcode_app_path() { return 1; }
xcode_selected_is_full() { return 1; }
xcode_has_ios_runtime() { return 1; }
EOF
    sed -i.bak "s|\. \".*/features/xcode/probe.sh\"|. \"$BATS_TEST_TMPDIR/fake-xcode-lib.sh\"|" \
        "$BATS_TEST_TMPDIR/completion.sh"
    sed -i.bak -e 's|^SIGNKEY=.*|SIGNKEY=""|' -e 's|^SIGNING=.*|SIGNING="1password"|' \
        "$BATS_TEST_TMPDIR/completion.sh"

    run bash "$BATS_TEST_TMPDIR/completion.sh"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^ *4\. chez sign'
    echo "$output" | grep -qE '^ *5\. chez xcode'
}

# The completion step's wording is the only thing that tells you *which* piece is
# missing, and the three states have three different fixes. A single "run
# chez xcode" for all of them would be a regression the earlier tests can't see.

# _completion_says MODULES DEVDIR HAS_APP HAS_RUNTIME — render the hook, stub the
# probes to describe that machine, run it, leave output in $output.
_completion_says() {
    _stub_config "$1"
    _render "$SRC_DIR/.chezmoiscripts/run_onchange_after_99-completion.sh.tmpl" \
        > "$BATS_TEST_TMPDIR/c.sh"
    cat > "$BATS_TEST_TMPDIR/fake.sh" <<EOF
xcode_app_path() { [ "$3" = 1 ] && { echo /Applications/Xcode.app; return 0; }; return 1; }
xcode_selected_is_full() { case "$2" in */Xcode*.app/Contents/Developer) return 0 ;; esac; return 1; }
xcode_has_ios_runtime() { [ "$4" = 1 ]; }
EOF
    sed -i.bak "s|\. \".*/features/xcode/probe.sh\"|. \"$BATS_TEST_TMPDIR/fake.sh\"|" \
        "$BATS_TEST_TMPDIR/c.sh"
    run bash "$BATS_TEST_TMPDIR/c.sh"
    [ "$status" -eq 0 ]
}

@test "completion step: no Xcode at all says so" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _completion_says '["appleDev"]' /Library/Developer/CommandLineTools 0 0
    [[ "$output" == *"No Xcode is installed"* ]] || return 1
}

@test "completion step: Xcode present but CLT selected names the toolchain" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _completion_says '["appleDev"]' /Library/Developer/CommandLineTools 1 0
    [[ "$output" == *"Command Line Tools are still the active toolchain"* ]] || return 1
    [[ "$output" != *"No Xcode is installed"* ]] || return 1
}

@test "completion step: only the runtime missing names the runtime" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _completion_says '["appleDev"]' /Applications/Xcode.app/Contents/Developer 1 0
    [[ "$output" == *"No iOS simulator runtime is downloaded"* ]] || return 1
    [[ "$output" != *"active toolchain"* ]] || return 1
}

# A ready machine must not be nagged — the step disappears entirely.
@test "completion step: a ready machine gets no chez xcode step" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _completion_says '["appleDev"]' /Applications/Xcode.app/Contents/Developer 1 1
    no_match_in "$output" 'chez xcode'
}
