#!/usr/bin/env bats
# Guards for the data that drives chezclean's reconciliation of $HOME and
# ~/.config, plus the storecode install hook — all sourced from
# src/.chezmoidata so they can't drift.
#
# chezclean reads three lists from cleanup.toml: keepConfig, keepHome, and
# owners (keep an entry while its owning tool/extension is present). If any
# render wrong, chezclean would offer an in-use dir for removal — these tests
# pin the render, the critical entries, the storecode exemption, and the
# 05-storecode hook's guards + never-fail-an-apply behaviour.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SRC_DIR="$REPO_ROOT/src"
    CLEANUP="$SRC_DIR/.chezmoidata/cleanup.toml"
    STORECODE_DATA="$SRC_DIR/.chezmoidata/storecode.toml"
    STORECODE_HOOK="$SRC_DIR/.chezmoiscripts/run_onchange_after_05-storecode.sh.tmpl"

    HAS_CHEZMOI=0
    command -v chezmoi >/dev/null 2>&1 && HAS_CHEZMOI=1
}

# Minimal chezmoi config so execute-template renders .chezmoidata-backed templates
# the same way CI does (mirrors tests/chezmoi-scripts.bats).
_setup_stub_chezmoi() {
    STUB_DIR="$BATS_TEST_TMPDIR/chezmoi-stub"
    mkdir -p "$STUB_DIR/home/.config/chezmoi" "$STUB_DIR/dst"
    cat >"$STUB_DIR/home/.config/chezmoi/chezmoi.toml" <<EOF
sourceDir = "$SRC_DIR"

[data]
    profile = "personal"
EOF
}

# Render an arbitrary template string against the source's .chezmoidata.
_render_str() {
    HOME="$STUB_DIR/home" XDG_CONFIG_HOME="$STUB_DIR/home/.config" \
        chezmoi execute-template \
        --config="$STUB_DIR/home/.config/chezmoi/chezmoi.toml" \
        --source="$SRC_DIR" "$1"
}

# The rendered tool-ownership map — the exact template chezclean reads: one
# "entry<TAB>package<TAB>binary<TAB>extension" row per cleanup.owners entry.
# dig-guarded so a missing map renders empty rather than erroring.
_render_owners() {
    _render_str '{{ range $e, $m := (dig "cleanup" "owners" (dict) .) }}{{ $e }}{{ "\t" }}{{ dig "package" "" $m }}{{ "\t" }}{{ dig "binary" "" $m }}{{ "\t" }}{{ dig "extension" "" $m }}{{ "\n" }}{{ end }}'
}

# Render the 05-storecode hook against a fake HOME (so {{ .chezmoi.homeDir }}
# points into it), returning only the logic BELOW the darwin/work template guards
# — the `home=` line onward — so the behavioural tests run identically on macOS
# and on Linux CI (where the darwin guard would otherwise short-circuit).
_render_storecode_body() { # $1 = fake HOME
    local rendered
    rendered="$(HOME="$1" XDG_CONFIG_HOME="$1/.config" chezmoi execute-template \
        --config="$STUB_DIR/home/.config/chezmoi/chezmoi.toml" \
        --source="$SRC_DIR" <"$STORECODE_HOOK")"
    printf '%s\n' "$rendered" | sed -n '/^home=/,$p'
}

# ─── keepConfig: the ~/.config keep-list chezclean spares ────────────────────

@test "the critical auth/state dirs are pinned in keepConfig (chezmoi first)" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    local keep first
    keep="$(_render_str '{{ range .cleanup.keepConfig }}{{ . }}{{ "\n" }}{{ end }}')"
    [ -n "$keep" ]
    # chezmoi's own config+state dir MUST come first — removing it breaks chezmoi.
    first="$(printf '%s\n' "$keep" | grep -m1 .)"
    [ "$first" = "chezmoi" ]
    local crit
    for crit in chezmoi op gh gcloud; do
        grep -qxF "$crit" <<<"$keep" || {
            echo "critical dir missing from keepConfig: $crit"
            return 1
        }
    done
}

# ─── storecode exemption ────────────────────────────────────────────────────

@test "storecode is exempt: ~/.storecode is on keepHome, never a Brewfile package" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    local keephome
    keephome="$(_render_str '{{ range .cleanup.keepHome }}{{ . }}{{ "\n" }}{{ end }}')"
    grep -qxF ".storecode" <<<"$keephome"
    ! grep -rqiE '(brew|cask)[[:space:]]+"[^"]*storecode' "$REPO_ROOT/packages/"
}

@test "keepHome pins the structurally-required exceptions" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    local keephome e
    keephome="$(_render_str '{{ range .cleanup.keepHome }}{{ . }}{{ "\n" }}{{ end }}')"
    # .config stays whole here (children reconciled separately vs keepConfig);
    # .ssh holds keys; .storecode is installed by 05-storecode; .swiftpm is
    # SwiftPM state with no `swiftpm` binary for the stem heuristic to match, so
    # without the pin chezclean offers to delete it on every appleDev machine.
    for e in .storecode .config .ssh .swiftpm; do
        grep -qxF "$e" <<<"$keephome" || {
            echo "keepHome missing required entry: $e"
            return 1
        }
    done
}

# ─── cleanup.owners: the tool-ownership map chezclean reads ───────────────────
# If this renders wrong (a lost binary, an empty row) chezclean would offer
# in-use config for removal.

@test "cleanup.owners renders as entry→package/binary/extension rows" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    local owners
    owners="$(_render_owners)"
    [ -n "$owners" ]
    grep -qxF $'.kube\tkubernetes-cli\tkubectl\t' <<<"$owners"
    # .m2 has no package (mise); the empty middle field must survive rendering
    # or the "mvn" binary would be lost.
    grep -qxF $'.m2\t\tmvn\t' <<<"$owners"
    # .sonarlint is extension-only (empty package+binary, three tabs before the
    # ID) — a collapsed middle field would land the extension in the binary slot.
    grep -qxF $'.sonarlint\t\t\tsonarsource.sonarlint-vscode' <<<"$owners"
}

@test "at least one owners row maps a binary that differs from its dir stem (alias exercised)" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    local owners
    owners="$(_render_owners)"
    # awk preserves empty fields (unlike read with a whitespace IFS).
    run awk -F'\t' '{ stem=$1; sub(/^\./,"",stem); sub(/\..*/,"",stem)
                      if ($3 != "" && $3 != stem) diverge++ }
                    END { exit (diverge > 0) ? 0 : 1 }' <<<"$owners"
    [ "$status" -eq 0 ]
}

@test "no owners row has package, binary AND extension all empty (every entry stays findable)" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    local owners
    owners="$(_render_owners)"
    run awk -F'\t' '$2 == "" && $3 == "" && $4 == "" { print }' <<<"$owners"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "every extension-owned owners row carries an extension ID (chezclean's extension signal)" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    local owners
    owners="$(_render_owners)"
    local dir
    for dir in .sonarlint .sts4 .codetogether .lemminx .vs-kubernetes; do
        awk -F'\t' -v d="$dir" '$1 == d && $4 != "" { found=1 } END { exit found ? 0 : 1 }' <<<"$owners" || {
            echo "extension-owned dir missing its extension ID: $dir"
            return 1
        }
    done
}

# ─── 05-storecode install hook ───────────────────────────────────────────────

@test "the storecode install hook is work-profile + darwin gated" {
    grep -qF '{{ if ne .chezmoi.os "darwin" -}}' "$STORECODE_HOOK"
    grep -qF '{{ if ne .profile "work" -}}' "$STORECODE_HOOK"
    grep -qF '.storecode.installCmd' "$STORECODE_HOOK"
    grep -qE '^\[storecode\]' "$STORECODE_DATA"
}

@test "05-storecode is idempotent: skips when ~/.storecode already exists" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    local fakehome="$BATS_TEST_TMPDIR/schome-present"
    mkdir -p "$fakehome/.storecode" # the "already installed" marker
    local body
    body="$(_render_storecode_body "$fakehome")"
    # PATH has no real `storecode`, so the skip is driven by the dir, not the host.
    run env PATH="/usr/bin:/bin" bash -c "$body"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
}

@test "05-storecode with no installer configured prints guidance and exits 0 (never fails an apply)" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    grep -qE '^installCmd = ""' "$STORECODE_DATA"
    local fakehome="$BATS_TEST_TMPDIR/schome-absent"
    mkdir -p "$fakehome" # no ~/.storecode, and storecode not on the stub PATH
    local body
    body="$(_render_storecode_body "$fakehome")"
    run env PATH="/usr/bin:/bin" bash -c "$body"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no installer is configured yet"* ]]
    [[ "$output" != *"already installed"* ]]
}
