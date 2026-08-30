#!/usr/bin/env bats
# xcodes-lib.bats — scripts/lib/xcodes.sh, the prebuilt-binary bootstrap that
# replaced `brew "xcodesorg/made/xcodes"`.
#
# The property under test: the binary is never installed unless it came from the
# pinned URL *and* matched the pinned sha256. A dotfiles repo that drops an
# unverified executable on PATH is worse than one that fails loudly, so every
# failure path below asserts the target file does not exist afterwards.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    BIN_DIR="$BATS_TEST_TMPDIR/localbin"
    SERVE="$BATS_TEST_TMPDIR/serve"
    mkdir -p "$STUBS" "$BIN_DIR" "$SERVE"

    # A stand-in "release archive": one executable named `xcodes`.
    printf '#!/bin/sh\necho 9.9.9\n' >"$SERVE/xcodes"
    chmod +x "$SERVE/xcodes"
    (cd "$SERVE" && zip -q xcodes.zip xcodes)
    GOOD_SHA="$(shasum -a 256 "$SERVE/xcodes.zip" | awk '{print $1}')"

    # `chezmoi data` stub — serves the pin the library reads.
    make_pin "$GOOD_SHA"

    # Every test below one describes what happens when xcodes is NOT installed,
    # and xcodes_bootstrap opens with `xcodes_installed && return 0`. Prepending
    # to PATH does not achieve that on a machine where the appleDev module has
    # actually installed xcodes: the real binary is still visible, every bootstrap
    # short-circuits, and four tests fail for a reason that has nothing to do with
    # what they assert. CI has no xcodes, so it never noticed.
    #
    # The one test that wants xcodes present plants its own stub in $STUBS.
    PATH="$STUBS:$(_path_without xcodes)"
    export PATH XCODES_BIN_DIR="$BIN_DIR"
}

# _path_without CMD — $PATH with every directory holding an executable CMD removed.
_path_without() {
    local out="" d
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        [ -x "$d/$1" ] && continue
        out="${out:+$out:}$d"
    done < <(printf '%s\n' "$PATH" | tr ':' '\n')
    printf '%s\n' "$out"
}

# make_pin SHA — rewrite the `chezmoi` stub so it reports SHA as the pinned sum.
make_pin() {
    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
cat <<'JSON'
{"xcodes":{"version":"9.9.9","url":"file://$SERVE/xcodes.zip","sha256":"$1"}}
JSON
EOF
    chmod +x "$STUBS/chezmoi"
}

load_lib() {
    # Ensure the guard doesn't carry over between tests in one shell.
    unset __DOTFILES_XCODES_SH
    # shellcheck source=/dev/null
    . "$REPO_ROOT/scripts/lib/xcodes.sh"
}

@test "pin values are read from chezmoi data" {
    load_lib
    [ "$(xcodes_pin version)" = "9.9.9" ]
    [ "$(xcodes_pin sha256)" = "$GOOD_SHA" ]
}

@test "bootstrap installs the binary when the checksum matches" {
    load_lib
    run xcodes_bootstrap
    [ "$status" -eq 0 ]
    [ -x "$BIN_DIR/xcodes" ]
    [ "$("$BIN_DIR/xcodes")" = "9.9.9" ]
}

@test "a checksum mismatch installs nothing and fails loudly" {
    make_pin "0000000000000000000000000000000000000000000000000000000000000000"
    load_lib
    run xcodes_bootstrap
    [ "$status" -ne 0 ]
    [[ "$output" == *"checksum mismatch"* ]] || return 1
    [ ! -e "$BIN_DIR/xcodes" ]
}

@test "an unreachable download installs nothing" {
    cat >"$STUBS/chezmoi" <<EOF
#!/usr/bin/env bash
cat <<'JSON'
{"xcodes":{"version":"9.9.9","url":"file://$SERVE/does-not-exist.zip","sha256":"$GOOD_SHA"}}
JSON
EOF
    chmod +x "$STUBS/chezmoi"
    load_lib
    run xcodes_bootstrap
    [ "$status" -ne 0 ]
    [ ! -e "$BIN_DIR/xcodes" ]
}

@test "a missing pin fails instead of guessing a version" {
    printf '#!/usr/bin/env bash\necho "{}"\n' >"$STUBS/chezmoi"
    chmod +x "$STUBS/chezmoi"
    load_lib
    run xcodes_bootstrap
    [ "$status" -ne 0 ]
    [[ "$output" == *"pin"* ]] || return 1
    [ ! -e "$BIN_DIR/xcodes" ]
}

@test "bootstrap is a no-op when xcodes is already on PATH" {
    printf '#!/usr/bin/env bash\necho 1.2.3\n' >"$STUBS/xcodes"
    chmod +x "$STUBS/xcodes"
    load_lib
    run xcodes_bootstrap
    [ "$status" -eq 0 ]
    # Nothing was fetched into the install dir — the existing one is left alone.
    [ ! -e "$BIN_DIR/xcodes" ]
}

@test "the appleDev Brewfile no longer declares the unbuildable formula" {
    run grep -c "xcodesorg" "$REPO_ROOT/packages/Brewfile.apple-dev"
    [ "$output" = "0" ]
}

@test "aria2 is kept — xcodes install still uses it" {
    grep -qE '^brew "aria2"' "$REPO_ROOT/packages/Brewfile.apple-dev"
}
