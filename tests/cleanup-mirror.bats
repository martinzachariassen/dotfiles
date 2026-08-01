#!/usr/bin/env bats
# Guards for the HOME-mirror mechanism: the ~/.config keep-list (exact_ dir +
# .chezmoiignore), its single source of truth (cleanup.toml), the storecode
# exemption, and 02c's dangling-symlink removal.
#
# Why this exists:
#   ~/.config is an exact_ dir (src/exact_dot_config), so `chezmoi apply` removes
#   any untracked top-level ~/.config/X. The ONLY thing that spares auth/state
#   dirs (op, gh, gcloud, chezmoi's own state) from that removal is the keep-list
#   rendered into .chezmoiignore from cleanup.keepConfig. If the two ever drift —
#   a keepConfig entry that never reaches .chezmoiignore — the next apply would
#   delete that dir on every machine. These tests pin the render, the critical
#   entries, and the exact_ switch itself, so a regression fails here, not in
#   $HOME.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SRC_DIR="$REPO_ROOT/src"
    IGNORE="$SRC_DIR/.chezmoiignore"
    CLEANUP="$SRC_DIR/.chezmoidata/cleanup.toml"
    STORECODE_DATA="$SRC_DIR/.chezmoidata/storecode.toml"
    SCRIPT_02C="$SRC_DIR/.chezmoiscripts/run_onchange_after_02c-cleanup-deprecated.sh.tmpl"
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

# The rendered .chezmoiignore (keep-list block expanded).
_render_ignore() {
    HOME="$STUB_DIR/home" XDG_CONFIG_HOME="$STUB_DIR/home/.config" \
        chezmoi execute-template \
        --config="$STUB_DIR/home/.config/chezmoi/chezmoi.toml" \
        --source="$SRC_DIR" <"$IGNORE"
}

# ─── the exact_ switch itself ───────────────────────────────────────────────

@test "the ~/.config source dir is exact_ (mirror switch is on)" {
    # exact_ is what makes chezmoi PRUNE untracked ~/.config entries. If the dir
    # ever reverts to plain dot_config the mirror silently stops enforcing.
    [ -d "$SRC_DIR/exact_dot_config" ]
    [ ! -d "$SRC_DIR/dot_config" ]
}

# ─── keepConfig ↔ .chezmoiignore: the safety net can't drift ────────────────

@test "every cleanup.keepConfig entry is protected in the rendered .chezmoiignore" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    local rendered keep
    rendered="$(_render_ignore)"
    keep="$(_render_str '{{ range .cleanup.keepConfig }}{{ . }}{{ "\n" }}{{ end }}')"
    [ -n "$keep" ]
    local entry
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        grep -qxF ".config/$entry" <<<"$rendered" || {
            echo "keepConfig entry not protected in .chezmoiignore: .config/$entry"
            return 1
        }
    done <<<"$keep"
}

@test "the critical auth/state dirs are pinned in keepConfig (chezmoi first)" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    local keep first
    keep="$(_render_str '{{ range .cleanup.keepConfig }}{{ . }}{{ "\n" }}{{ end }}')"
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
    # It must NOT be declared in any Brewfile tier (installed by its own script).
    ! grep -rqiE '(brew|cask)[[:space:]]+"[^"]*storecode' "$REPO_ROOT/packages/"
}

@test "keepHome pins the structurally-required exceptions" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    local keephome e
    keephome="$(_render_str '{{ range .cleanup.keepHome }}{{ . }}{{ "\n" }}{{ end }}')"
    # .config is governed by exact_+keepConfig (not chezclean); .ssh holds keys.
    for e in .storecode .config .ssh; do
        grep -qxF "$e" <<<"$keephome" || {
            echo "keepHome missing required entry: $e"
            return 1
        }
    done
}

@test "the storecode install hook is work-profile + darwin gated" {
    grep -qF '{{ if ne .chezmoi.os "darwin" -}}' "$STORECODE_HOOK"
    grep -qF '{{ if ne .profile "work" -}}' "$STORECODE_HOOK"
    # Install command is data-driven from storecode.toml, not hardcoded.
    grep -qF '.storecode.installCmd' "$STORECODE_HOOK"
    grep -qE '^\[storecode\]' "$STORECODE_DATA"
}

# ─── 02c: dangling-symlink removal (the -e → -L regression) ──────────────────

@test "02c source tests -L so a dangling symlink is caught, not just -e" {
    # `[ -e ]` follows a symlink and FAILS on a dangling one, so the pre-fix loop
    # silently skipped ~/.nix-profile. Pin that both the path loop and the symlink
    # loop test -L.
    grep -qF 'if [ -e "$p" ] || [ -L "$p" ]; then' "$SCRIPT_02C"
    grep -qF 'if [ -L "$s" ] || [ -e "$s" ]; then' "$SCRIPT_02C"
}

@test "02c actually removes a dangling symlink when rendered" {
    [ "$HAS_CHEZMOI" -eq 1 ] || skip "chezmoi not installed"
    _setup_stub_chezmoi
    local fakehome="$BATS_TEST_TMPDIR/fakehome"
    mkdir -p "$fakehome"
    # A dangling symlink (target never exists): fails -e, passes -L.
    ln -s "$fakehome/never-exists" "$fakehome/.nix-profile"
    [ -L "$fakehome/.nix-profile" ]
    [ ! -e "$fakehome/.nix-profile" ]

    # Render 02c with HOME=fakehome so the baked DEPRECATED_SYMLINKS points into
    # it, then run ONLY the symlink array + its removal loop — skipping the darwin
    # guard and the brew section (which would call brew / early-exit on Linux).
    local rendered snippet
    rendered="$(HOME="$fakehome" XDG_CONFIG_HOME="$fakehome/.config" chezmoi execute-template \
        --config="$STUB_DIR/home/.config/chezmoi/chezmoi.toml" \
        --source="$SRC_DIR" <"$SCRIPT_02C")"
    snippet="$(printf '%s\n' "$rendered" | sed -n '/^DEPRECATED_SYMLINKS=(/,/^)/p')"$'\n'
    snippet+="removed_any=false"$'\n'
    snippet+="$(printf '%s\n' "$rendered" | sed -n '/^for s in /,/^done/p')"

    run bash -c "$snippet"
    [ "$status" -eq 0 ]
    [[ "$output" == *"removing symlink"* ]]
    [ ! -L "$fakehome/.nix-profile" ]  # the dangling link is gone
}
