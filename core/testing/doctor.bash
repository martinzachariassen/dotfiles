#!/usr/bin/env bash
# doctor.bash — the shared harness for driving `chez doctor` from a bats suite.
#
# The runner is one script but its checks live with their features, so four
# suites need the same isolated machine: a scratch $HOME, a scratch repo for
# DOTFILES_DIR to point at, and a PATH with no Homebrew on it — so every section
# whose tool is absent short-circuits to "not installed" instead of reporting on
# the machine the tests happen to run on.
#
#   load '../../../core/testing/helper'
#   load '../../../core/testing/doctor'

# doctor_iso_setup — call from setup(), after loading helper.bash.
doctor_iso_setup() {
    DOCTOR="$REPO_ROOT/features/doctor/cli.sh"
    command -v git >/dev/null 2>&1 || skip "git not installed"

    ISO_HOME="$BATS_TEST_TMPDIR/home"
    ISO_REPO="$BATS_TEST_TMPDIR/repo"
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$ISO_HOME" "$ISO_REPO" "$STUB_BIN"
    # Real coreutils and git, nothing from Homebrew.
    ISO_PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"

    # An empty global git config, for two reasons. The report reads
    # `git config --global user.email`, so without this the assertions depend on
    # who is running them. And `core.fsmonitor = true` — which this repo's own
    # gitconfig sets — makes `git status` in the scratch repo spawn a *detached*
    # fsmonitor daemon that inherits the bats output pipe and never exits, so
    # the whole run reports every test green and then hangs forever.
    ISO_GITCONFIG="$BATS_TEST_TMPDIR/gitconfig"
    : >"$ISO_GITCONFIG"
}

# doctor_run — run the report against the isolated machine. DOTFILES_DIR names
# the repo under test; the runner still finds its own code beside itself.
doctor_run() {
    run env HOME="$ISO_HOME" DOTFILES_DIR="$ISO_REPO" PATH="$ISO_PATH" \
        GIT_CONFIG_GLOBAL="$ISO_GITCONFIG" GIT_CONFIG_SYSTEM=/dev/null bash "$DOCTOR"
}

# doctor_run_with PATH — same, with a PATH of your own (see doctor_path_with).
doctor_run_with() {
    run env HOME="$ISO_HOME" DOTFILES_DIR="$ISO_REPO" PATH="$1" \
        GIT_CONFIG_GLOBAL="$ISO_GITCONFIG" GIT_CONFIG_SYSTEM=/dev/null "${@:2}" bash "$DOCTOR"
}

# doctor_git_init — a scratch repo the report can look at, created with the
# isolated config so no fsmonitor daemon is left behind.
doctor_git_init() {
    (cd "$ISO_REPO" &&
        GIT_CONFIG_GLOBAL="$ISO_GITCONFIG" GIT_CONFIG_SYSTEM=/dev/null git init -q -b main)
}

# doctor_stub_chezmoi VERSION [MODULES_JSON] — a chezmoi that answers the four
# things the report asks it: its version, this Mac's data, and two clean exits.
doctor_stub_chezmoi() {
    local version="$1" modules="${2:-[]}"
    cat >"$STUB_BIN/chezmoi" <<EOF
#!/usr/bin/env bash
case "\$1" in
    --version) echo "chezmoi version $version, commit none, built none" ;;
    data) echo '{"modules":$modules,"profile":"personal"}' ;;
    doctor | status) exit 0 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$STUB_BIN/chezmoi"
}

# doctor_path_with CMD — ISO_PATH plus the real directory holding CMD. The
# module gate goes through jq, which the isolated PATH deliberately lacks.
doctor_path_with() {
    local bin
    bin="$(command -v "$1" 2>/dev/null)" || return 1
    printf '%s:%s:%s' "$STUB_BIN" "$(dirname "$bin")" "/usr/bin:/bin:/usr/sbin:/sbin"
}
