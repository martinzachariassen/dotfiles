#!/usr/bin/env bats
# Coverage for features/brew/lib/tiers.sh — the single answer to "which Brewfile
# tiers apply to THIS machine?", shared by chezdoctor and by chezmirror's
# removal set so the install and removal directions can't disagree.
#
# Both directions used to resolve it separately: installs were gated on profile
# + modules, removals globbed every `Brewfile.*` that existed. A cask moved
# from a module tier to the work profile therefore stayed "tracked" on a
# personal machine and was never offered for uninstall.

setup() {
    load '../../../core/testing/helper'
    LIB="$REPO_ROOT/features/brew/lib/tiers.sh"
    command -v jq >/dev/null 2>&1 || skip "jq not installed (brew_active_files needs it)"

    # Mirrors src/.chezmoidata/brew.toml's shape; both tiers of both
    # profiles and both optional modules exist, so every test below is really
    # about selection, not about which files happen to be defined.
    DATA='{"profile":"personal","modules":["macApps","theme"],"brewfiles":{
        "core":"features/brew/Brewfile",
        "byModule":{"macApps":"features/brew/Brewfile.mac-apps","appleDev":"features/brew/Brewfile.apple-dev"},
        "byProfile":{"personal":"features/brew/Brewfile.personal","work":"features/brew/Brewfile.work"}}}'
}

resolve() { # resolve JSON — run brew_active_files against fixture data
    run bash -c ". '$LIB'; brew_active_files \"\$1\"" _ "$1"
}

# Negative assertions must go through this. A bare `! grep …` in the middle of
# a test body is exempt from set -e (POSIX: "the return value is being inverted
# with !"), so bats never sees it fail.
#
# no_match_in <text> <extended-regex>
no_match_in() {
    if grep -qE "$2" <<<"$1"; then
        echo "unexpected match for: $2"
        return 1
    fi
}

@test "brew_active_files emits core + enabled modules + this profile" {
    resolve "$DATA"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "features/brew/Brewfile" ]
    [ "${lines[1]}" = "features/brew/Brewfile.mac-apps" ]
    [ "${lines[2]}" = "features/brew/Brewfile.personal" ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "brew_active_files drops the other profile's tier" {
    # The chezmirror bug in one assertion: on personal, work is NOT tracked.
    resolve "$DATA"
    no_match_in "$output" 'Brewfile\.work'
}

@test "brew_active_files drops a module the machine hasn't enabled" {
    resolve "$DATA"
    no_match_in "$output" 'apple-dev'
}

@test "brew_active_files picks up a module once it's enabled" {
    resolve "$(jq -c '.modules += ["appleDev"]' <<<"$DATA")"
    [ "$status" -eq 0 ]
    grep -qF 'features/brew/Brewfile.apple-dev' <<<"$output"
}

@test "brew_active_files follows the profile switch" {
    resolve "$(jq -c '.profile = "work"' <<<"$DATA")"
    [ "$status" -eq 0 ]
    grep -qF 'features/brew/Brewfile.work' <<<"$output"
    no_match_in "$output" 'Brewfile\.personal'
}

@test "brew_active_files orders core first, profile last (install order)" {
    # Same order run_after_02-brew-bundle installs in: core, modules, profile.
    resolve "$(jq -c '.modules += ["appleDev"]' <<<"$DATA")"
    [ "${lines[0]}" = "features/brew/Brewfile" ]
    [ "${lines[$((${#lines[@]} - 1))]}" = "features/brew/Brewfile.personal" ]
}

@test "brew_active_files survives a profile with no Brewfile of its own" {
    # The lookup is null and must be dropped — not emitted as the string
    # "null", which callers would turn into a bogus \$SOURCE_DIR/null path.
    resolve "$(jq -c '.profile = "minimal"' <<<"$DATA")"
    [ "$status" -eq 0 ]
    no_match_in "$output" '^null$'
    grep -qF 'features/brew/Brewfile' <<<"$output"
}

@test "brew_active_files survives absent modules/byModule keys" {
    resolve '{"profile":"personal","brewfiles":{"core":"features/brew/Brewfile","byProfile":{"personal":"p"}}}'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "features/brew/Brewfile" ]
    [ "${lines[1]}" = "p" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "brew_active_files yields nothing for data with no brewfiles map" {
    # Must be empty, not a partial list: callers fail closed on empty, and an
    # under-resolved set would offer the whole toolchain for uninstall.
    resolve '{}'
    [ -z "$output" ]
}

@test "brew_active_files falls back to \`chezmoi data\` when passed no JSON" {
    stub="$(mktemp -d)"
    cat >"$stub/chezmoi" <<'EOF'
#!/usr/bin/env bash
[ "$1" = data ] && printf '%s' "$FAKE_DATA"
EOF
    chmod +x "$stub/chezmoi"
    run env PATH="$stub:$PATH" FAKE_DATA="$DATA" bash -c ". '$LIB'; brew_active_files"
    rm -rf "$stub"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "features/brew/Brewfile" ]
}

@test "brew_active_files fails when chezmoi data yields nothing" {
    # Fail, don't guess: callers treat a non-zero/empty resolve as "offer
    # nothing for removal", which is the only safe direction to be wrong in.
    stub="$(mktemp -d)"
    printf '#!/usr/bin/env bash\nexit 1\n' >"$stub/chezmoi"
    chmod +x "$stub/chezmoi"
    run env PATH="$stub:/usr/bin:/bin" bash -c ". '$LIB'; brew_active_files"
    rm -rf "$stub"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "brew_active_files is idempotent when sourced twice" {
    # doctor.sh and the zsh verbs can both pull it in; the include guard must
    # not turn the second source into a failure.
    run bash -c ". '$LIB'; . '$LIB'; brew_active_files '$DATA'"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "features/brew/Brewfile" ]
}
