#!/usr/bin/env bats
# Coverage for doctor.sh's deterministic, offline-stubbable sections: XDG
# layout, source-repo presence, and the chezmoi-version floor check. Sections
# needing real gh/az/gcloud/brew/code/mise/op state aren't covered here —
# doctor.sh has no seam to inject fake credentials for those, and this repo's
# CI runner doesn't have them installed anyway.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    DOCTOR="$REPO_ROOT/scripts/bin/doctor.sh"
    command -v git >/dev/null 2>&1 || skip "git not installed"

    ISO_HOME="$(mktemp -d)"
    ISO_REPO="$(mktemp -d)"
    STUB_BIN="$(mktemp -d)"
    # A minimal, deterministic PATH: real coreutils/git only, no
    # Homebrew-installed brew/code/mise/gh/az/gcloud/op — so those sections
    # short-circuit to "not installed" instead of exercising real machine
    # state (which would make this test's output nondeterministic and slow).
    ISO_PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
}

teardown() {
    rm -rf "${ISO_HOME:-}" "${ISO_REPO:-}" "${STUB_BIN:-}"
}

run_doctor() {
    run env HOME="$ISO_HOME" DOTFILES_DIR="$ISO_REPO" PATH="$ISO_PATH" bash "$DOCTOR"
}

# ─── XDG layout ─────────────────────────────────────────────────────────────

@test "doctor.sh fails when a legacy .zshrc is present" {
    touch "$ISO_HOME/.zshrc"
    run_doctor
    [[ "$output" == *"legacy $ISO_HOME/.zshrc present"* ]]
}

@test "doctor.sh passes XDG layout when only the managed files exist" {
    mkdir -p "$ISO_HOME/.config/zsh"
    touch "$ISO_HOME/.config/zsh/.zshrc" "$ISO_HOME/.zshenv"
    run_doctor
    [[ "$output" == *"~/.config/zsh/.zshrc present"* ]]
    [[ "$output" == *"~/.zshenv present"* ]]
    [[ "$output" == *"no legacy .zshrc"* ]]
    [[ "$output" != *"legacy $ISO_HOME"* ]]
}

@test "doctor.sh fails when ~/.config/zsh/.zshrc is missing" {
    run_doctor
    [[ "$output" == *"~/.config/zsh/.zshrc missing"* ]]
}

# ─── Source repo ────────────────────────────────────────────────────────────

@test "doctor.sh fails when DOTFILES_DIR has no .git" {
    run_doctor
    [[ "$output" == *"repo missing at $ISO_REPO"* ]]
}

@test "doctor.sh passes repo presence and clean-tree checks for a real git repo" {
    (cd "$ISO_REPO" && git init -q -b main)
    run_doctor
    [[ "$output" == *"repo at $ISO_REPO"* ]]
    [[ "$output" == *"repo working tree clean"* ]]
}

# ─── chezmoi version comparison ─────────────────────────────────────────────

stub_chezmoi() {
    local version="$1"
    cat >"$STUB_BIN/chezmoi" <<EOF
#!/usr/bin/env bash
case "\$1" in
    --version) echo "chezmoi version $version, commit none, built none" ;;
    doctor) exit 0 ;;
    status) exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$STUB_BIN/chezmoi"
}

@test "doctor.sh fails when the installed chezmoi is older than the repo floor" {
    (cd "$ISO_REPO" && git init -q -b main)
    mkdir -p "$ISO_REPO/src"
    echo "2.50.0" >"$ISO_REPO/src/.chezmoiversion"
    stub_chezmoi "v2.40.0"
    run_doctor
    [[ "$output" == *"chezmoi 2.40.0 is older than the repo minimum 2.50.0"* ]]
}

@test "doctor.sh passes when the installed chezmoi meets the repo floor" {
    (cd "$ISO_REPO" && git init -q -b main)
    mkdir -p "$ISO_REPO/src"
    echo "2.50.0" >"$ISO_REPO/src/.chezmoiversion"
    stub_chezmoi "v2.72.0"
    run_doctor
    [[ "$output" == *"chezmoi 2.72.0 meets repo minimum 2.50.0"* ]]
}
