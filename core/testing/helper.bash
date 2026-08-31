#!/usr/bin/env bash
# helper.bash — shared bats setup. Load it as the first line of a suite's
# setup(), with a path relative to the suite:
#
#   load '../../core/testing/helper'          # from tests/
#   load '../../../core/testing/helper'       # from features/<name>/tests/
#
# Existing suites each redefine REPO_ROOT by hand; they adopt this as their
# feature moves, rather than in one sweep.

# REPO_ROOT — found by walking up to .chezmoiroot, so it does not care how deep
# the suite sits. ZSHRC is here because eight suites want it.
_helper_init() {
    local d="$BATS_TEST_DIRNAME"

    # Pin the machine-local dirs into the test's own tmpdir, ALWAYS.
    #
    # core/paths.sh otherwise resolves them under the real $HOME, so any suite
    # touching the Brewfile overlay would read whatever the person running it
    # happens to keep there — green on CI, where the file does not exist, and
    # red (or worse, wrongly green) on a Mac that has adopted a package. That is
    # the same non-hermeticity that made the distill corpus suite depend on
    # whose laptop it ran on. A test that wants an overlay writes one here.
    export CHEZ_CONFIG_DIR="$BATS_TEST_TMPDIR/chez-config"
    export CHEZ_STATE_DIR="$BATS_TEST_TMPDIR/chez-state"

    while [ "$d" != "/" ]; do
        if [ -f "$d/.chezmoiroot" ]; then
            REPO_ROOT="$d"
            ZSHRC="$d/src/dot_config/zsh/dot_zshrc.tmpl"
            return 0
        fi
        d="$(dirname "$d")"
    done
    printf 'helper.bash: no .chezmoiroot above %s\n' "$BATS_TEST_DIRNAME" >&2
    return 1
}
_helper_init

# no_match REGEX FILE… — a negative grep that actually fails the test.
#
# A bare `! grep …` is exempt from bats' failure detection (POSIX: the return
# value is being inverted), so the assertion silently passes whatever the file
# contains. A function call is not exempt. Same reason every bare `[[ ]]` in
# this repo carries `|| return 1` — see docs/development.md.
no_match() {
    if grep -qE "$@"; then
        printf 'unexpected match for: %s\n' "$1" >&2
        return 1
    fi
}

# no_match_in TEXT REGEX — the same assertion against a string, usually $output.
# Argument order is TEXT first to read as "no match in this, for that".
no_match_in() {
    if grep -qE "$2" <<<"$1"; then
        printf 'unexpected match for: %s\n' "$2" >&2
        return 1
    fi
}

# skip_unless CMD [REASON] — skip when a tool is not installed.
skip_unless() {
    command -v "$1" >/dev/null 2>&1 || skip "${2:-$1 not installed}"
}

# stub_bin DIR NAME BODY — write an executable stub and echo nothing. Prepend
# DIR to PATH yourself; suites differ on how much of the real PATH they keep.
stub_bin() {
    local dir="$1" name="$2" body="$3"
    mkdir -p "$dir"
    {
        printf '#!/usr/bin/env bash\n'
        printf '%s\n' "$body"
    } >"$dir/$name"
    chmod +x "$dir/$name"
}

# ── chezmoi rendering ────────────────────────────────────────────────────────
# Several suites need to render a template against the repo's real .chezmoidata.
# Doing it by hand takes twenty lines of stub config, and three suites had their
# own copy.

# chezmoi_stub_config [DATA…] — write a minimal chezmoi config into
# $BATS_TEST_TMPDIR and set STUB_DIR/SRC_DIR. Extra args are appended verbatim
# inside [data], one per line.
chezmoi_stub_config() {
    SRC_DIR="$REPO_ROOT/src"
    STUB_DIR="$BATS_TEST_TMPDIR/chezmoi-stub"
    mkdir -p "$STUB_DIR/home/.config/chezmoi" "$STUB_DIR/dst"
    # No keys of its own. This used to seed `profile = "personal"` for every
    # caller, which outlived the profile axis itself: a suite that never
    # mentioned the profile still rendered against a config carrying it, and so
    # exercised the un-migrated path without meaning to. A suite that wants the
    # retired key now says so.
    {
        printf 'sourceDir = "%s"\n\n[data]\n' "$SRC_DIR"
        local extra
        for extra in "$@"; do printf '    %s\n' "$extra"; done
    } >"$STUB_DIR/home/.config/chezmoi/chezmoi.toml"
}

# chezmoi_render_str TEMPLATE — render one template string against .chezmoidata.
chezmoi_render_str() {
    HOME="$STUB_DIR/home" XDG_CONFIG_HOME="$STUB_DIR/home/.config" \
        chezmoi execute-template \
        --config="$STUB_DIR/home/.config/chezmoi/chezmoi.toml" \
        --source="$SRC_DIR" "$1"
}

# chezmoi_render_file FILE [HOME] — render a template file, optionally against a
# fake HOME so {{ .chezmoi.homeDir }} points into it.
chezmoi_render_file() {
    local home="${2:-$STUB_DIR/home}"
    HOME="$home" XDG_CONFIG_HOME="$home/.config" \
        chezmoi execute-template \
        --config="$STUB_DIR/home/.config/chezmoi/chezmoi.toml" \
        --source="$SRC_DIR" <"$1"
}
