#!/usr/bin/env bats
# Coverage for features/brew/lib/tiers.sh — the single answer to "which Brewfile
# tiers apply to THIS machine?", shared by chez doctor and by chez mirror's
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
    # The chez mirror bug in one assertion: on personal, work is NOT tracked.
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

# ── brew_bare_names ──────────────────────────────────────────────────────────
# The comparison key behind doctor's untracked-package check. It exists because
# the two sides of that comparison are spelled differently: `brew leaves`
# reports a tap formula qualified (hashicorp/tap/terraform), a Brewfile may
# declare it either way, and tap owners carry capitals the installed name
# drops. doctor normalised only the Brewfile side, so every tap-installed
# package was reported as untracked on every run, forever.

bare() { run bash -c ". '$LIB'; brew_bare_names" <<<"$1"; }

@test "brew_bare_names strips the tap prefix" {
    bare 'hashicorp/tap/terraform'
    [ "$output" = "terraform" ] || return 1
}

@test "brew_bare_names folds the case a tap owner carries" {
    # Brewfile.work says `brew "Azure/kubelogin/kubelogin"`; brew leaves prints
    # azure/kubelogin/kubelogin. Same package, and they must compare equal.
    bare 'Azure/kubelogin/kubelogin'
    [ "$output" = "kubelogin" ] || return 1
}

@test "brew_bare_names leaves a core formula untouched" {
    bare 'jq'
    [ "$output" = "jq" ] || return 1
}

@test "brew_bare_names sorts, dedupes and drops blank lines" {
    bare 'zoxide
hashicorp/tap/terraform

terraform
jq'
    [ "${#lines[@]}" -eq 3 ] || return 1
    [ "${lines[0]}" = "jq" ] || return 1
    [ "${lines[1]}" = "terraform" ] || return 1
    [ "${lines[2]}" = "zoxide" ] || return 1
}

@test "a tap formula declared qualified is tracked, not untracked" {
    # The end-to-end shape of doctor's comparison: installed side qualified,
    # declared side straight out of a Brewfile. comm must find no difference.
    local leaves declared
    leaves=$(bash -c ". '$LIB'; brew_bare_names" <<<'azure/kubelogin/kubelogin
hashicorp/tap/terraform')
    declared=$(bash -c ". '$LIB'; brew_bare_names" <<<'Azure/kubelogin/kubelogin
hashicorp/tap/terraform')
    run comm -23 <(printf '%s\n' "$leaves") <(printf '%s\n' "$declared")
    [ -z "$output" ] || return 1
}

# ── brew_untracked_of_kind ───────────────────────────────────────────────────
# "What is installed that no active tier declares?", asked one namespace at a
# time. Casks were invisible to this question for a long time: doctor's
# installed side was `brew leaves`, which lists formulae only, so an undeclared
# cask went unreported while chez status and chez mirror both saw it.

# bf <name> <line…> — a throwaway Brewfile, path echoed on stdout
bf() {
    local f="$BATS_TEST_TMPDIR/$1"
    shift
    printf '%s\n' "$@" >"$f"
    printf '%s' "$f"
}

untracked_of() { # untracked_of KIND INSTALLED FILE…
    run bash -c '. "$1"; shift; brew_untracked_of_kind "$@"' _ "$LIB" "$@"
}

@test "brew_untracked_of_kind reports an installed cask no tier declares" {
    local f
    f=$(bf Brewfile 'cask "rectangle"' 'brew "jq"')
    untracked_of cask 'rectangle
transmit' "$f"
    [ "$output" = "transmit" ] || return 1
}

@test "brew_untracked_of_kind stays quiet when every cask is declared" {
    local f
    f=$(bf Brewfile 'cask "rectangle"' 'cask "ghostty"')
    untracked_of cask 'ghostty
rectangle' "$f"
    [ -z "$output" ] || return 1
}

@test "brew_untracked_of_kind does not let a cask vouch for a formula" {
    # docker exists as a formula AND as a cask. Declaring the cask must not
    # make an undeclared formula of the same name read as tracked — the bug a
    # single merged namespace would reintroduce.
    local f
    f=$(bf Brewfile 'cask "docker"')
    untracked_of brew 'docker' "$f"
    [ "$output" = "docker" ] || return 1
}

@test "brew_untracked_of_kind ignores the other kind's declarations" {
    local f
    f=$(bf Brewfile 'brew "rectangle"')
    untracked_of cask 'rectangle' "$f"
    [ "$output" = "rectangle" ] || return 1
}

@test "brew_untracked_of_kind matches a tap-qualified cask declaration" {
    local f
    f=$(bf Brewfile 'cask "homebrew/cask-versions/firefox-beta"')
    untracked_of cask 'firefox-beta' "$f"
    [ -z "$output" ] || return 1
}

@test "brew_untracked_of_kind unions every tier it is given" {
    local a b
    a=$(bf Brewfile 'brew "jq"')
    b=$(bf Brewfile.work 'brew "hashicorp/tap/terraform"')
    untracked_of brew 'jq
terraform
ripgrep' "$a" "$b"
    [ "$output" = "ripgrep" ] || return 1
}

@test "brew_untracked_of_kind reports everything when no tier declares anything" {
    local f
    f=$(bf Brewfile '# nothing here')
    untracked_of brew 'jq
ripgrep' "$f"
    [ "${#lines[@]}" -eq 2 ] || return 1
}

@test "brew_untracked_of_kind refuses an empty tier set rather than hanging" {
    # `grep -h PATTERN` with zero file operands reads stdin and would hang the
    # run forever. Fail closed instead: no files means no answer, not "all
    # installed packages are untracked".
    untracked_of cask 'rectangle'
    [ "$status" -eq 1 ] || return 1
    [ -z "$output" ] || return 1
}

@test "brew_untracked_of_kind handles an empty installed list" {
    local f
    f=$(bf Brewfile 'cask "rectangle"')
    untracked_of cask '' "$f"
    [ "$status" -eq 0 ] || return 1
    [ -z "$output" ] || return 1
}
