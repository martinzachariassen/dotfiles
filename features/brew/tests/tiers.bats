#!/usr/bin/env bats
# Coverage for features/brew/lib/tiers.sh — the single answer to "which Brewfile
# tiers apply to THIS machine?", shared by chez doctor and by chez mirror's
# removal set so the install and removal directions can't disagree.
#
# Both directions used to resolve it separately: installs were gated on the
# module set, removals globbed every `Brewfile.*` that existed. A cask moved
# from one tier to another therefore stayed "tracked" on a machine that had
# stopped declaring it, and was never offered for uninstall.

setup() {
    load '../../../core/testing/helper'
    LIB="$REPO_ROOT/features/brew/lib/tiers.sh"
    command -v jq >/dev/null 2>&1 || skip "jq not installed (brew_active_files needs it)"

    # Mirrors src/.chezmoidata/brew.toml's shape; both optional module tiers
    # exist, so every test below is really about selection, not about which
    # files happen to be defined.
    DATA='{"modules":["macApps","theme"],"brewfiles":{
        "core":"features/brew/Brewfile",
        "byModule":{"macApps":"features/brew/Brewfile.mac-apps","appleDev":"features/brew/Brewfile.apple-dev"}}}'
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

@test "brew_active_files emits core + enabled modules" {
    resolve "$DATA"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "features/brew/Brewfile" ]
    [ "${lines[1]}" = "features/brew/Brewfile.mac-apps" ]
    [ "${#lines[@]}" -eq 2 ]
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

@test "brew_active_files orders core first (install order)" {
    # Same order run_after_02-brew-bundle installs in: core, then modules.
    resolve "$(jq -c '.modules += ["appleDev"]' <<<"$DATA")"
    [ "${lines[0]}" = "features/brew/Brewfile" ]
}

@test "brew_active_files survives absent modules/byModule keys" {
    resolve '{"brewfiles":{"core":"features/brew/Brewfile"}}'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "features/brew/Brewfile" ]
    [ "${#lines[@]}" -eq 1 ]
}

# ── the v1.0 migration's fail-closed guard ───────────────────────────────────
# Between pulling v1.0 and running an apply, a Mac can be executing this code
# against a config that still says `profile = "work"`: the profile tiers are
# gone from the repo, the migration hook has not run, and Brewfile.local does
# not exist yet. Resolving anyway would silently collapse "declared" to core
# plus modules — and the removal verbs would line the whole work stack up for
# uninstall. Refusing is the only safe reading of that state.

@test "brew_active_files refuses a config that still carries a profile key" {
    # stderr is discarded, not merged: `run` folds both streams together, and
    # the refusal explains itself on stderr. What must be empty is *stdout* —
    # a caller pipes it into the removal set and reads any line as declared.
    run bash -c ". '$LIB'; brew_active_files \"\$1\" 2>/dev/null" _ \
        "$(jq -c '.profile = "work"' <<<"$DATA")"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "the refusal is on the key's PRESENCE, not on its value" {
    # A migration that blanked the value instead of deleting the line would
    # otherwise disarm the guard while leaving the machine un-migrated.
    resolve "$(jq -c '.profile = ""' <<<"$DATA")"
    [ "$status" -eq 1 ]
    resolve "$(jq -c '.profile = null' <<<"$DATA")"
    [ "$status" -eq 1 ]
}

@test "the refusal names the fix on stderr" {
    run bash -c ". '$LIB'; brew_active_files \"\$1\" 2>&1 >/dev/null" _ \
        "$(jq -c '.profile = "work"' <<<"$DATA")"
    grep -qF 'profile' <<<"$output"
    grep -qF 'chez up' <<<"$output"
}

@test "a migrated config resolves normally again" {
    resolve "$(jq -c 'del(.profile)' <<<"$(jq -c '.profile = "work"' <<<"$DATA")")"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "features/brew/Brewfile" ]
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

# ── the machine-local overlay ────────────────────────────────────────────────
# ~/.config/chez/Brewfile.local is how a Mac says "this package is mine, on
# purpose". It is read as one more tier, so an adopted package is declared in
# exactly the sense a repo package is — which is what stops chez mirror offering
# it. helper.bash pins CHEZ_CONFIG_DIR into the test tmpdir, so none of this
# touches the overlay of whoever is running the suite.

# overlay LINE… — write the machine-local Brewfile.
overlay() {
    mkdir -p "$CHEZ_CONFIG_DIR"
    printf '%s\n' "$@" >"$CHEZ_CONFIG_DIR/Brewfile.local"
}

@test "the overlay is not emitted when the Mac has none" {
    resolve "$DATA"
    [ "${#lines[@]}" -eq 2 ]
    no_match_in "$output" 'Brewfile\.local'
}

@test "the overlay is emitted last, after every repo tier" {
    # Last so it can only ADD to the declared set. Emitting it earlier would
    # reorder the install, and `brew bundle` applies tiers in the order given.
    overlay 'brew "ffmpeg"'
    resolve "$DATA"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    [ "${lines[0]}" = "features/brew/Brewfile" ]
    [ "${lines[2]}" = "$CHEZ_CONFIG_DIR/Brewfile.local" ]
}

@test "the overlay is emitted absolute, not repo-relative" {
    # It lives outside the checkout, so a caller that prefixed the repo root
    # would resolve it to a path that does not exist and silently drop it —
    # which reads as "declared nothing" and puts every adopted package back on
    # the removal list. brew_resolve_file is what keeps callers honest.
    overlay 'brew "ffmpeg"'
    resolve "$DATA"
    [[ "${lines[2]}" == /* ]] || return 1
}

@test "an overlay does not rescue a failed resolve" {
    # The fail-closed contract. A jq failure must stay a failure even when the
    # overlay exists: returning 0 with one tier would tell every caller that the
    # machine declares almost nothing, and chez mirror would offer the rest of it
    # for uninstall. Appending the overlay after a bare pipeline would have made
    # the function's exit status the overlay's — this is why it is captured.
    overlay 'brew "ffmpeg"'
    resolve 'this is not json'
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

# ── brew_seed_local_brewfile ─────────────────────────────────────────────────

seed() { run bash -c ". '$LIB'; brew_seed_local_brewfile '$1'"; }

@test "seeding creates the overlay from the shipped template" {
    # A hatch nobody knows about is not a hatch: the apply hook writes the file
    # on every Mac so it explains itself in place, rather than only in the repo.
    seed "$REPO_ROOT"
    [ "$status" -eq 0 ]
    grep -q 'packages THIS Mac keeps' "$CHEZ_CONFIG_DIR/Brewfile.local"
}

@test "a seeded overlay declares nothing" {
    # Every line is a comment, so seeding cannot change what this Mac installs
    # or what the removal verbs spare. It is discoverability, not configuration.
    seed "$REPO_ROOT"
    no_match '^[[:space:]]*(brew|cask|tap|mas|vscode) ' "$CHEZ_CONFIG_DIR/Brewfile.local"
}

@test "seeding never touches an overlay that already exists" {
    # It runs on every apply. Rewriting the file would silently discard every
    # package this Mac had adopted.
    overlay 'brew "ffmpeg"'
    seed "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [ "$(cat "$CHEZ_CONFIG_DIR/Brewfile.local")" = 'brew "ffmpeg"' ]
}

@test "seeding falls back to a header when the template is missing" {
    # The template is a repo file and the seeder runs from a hook; an incomplete
    # checkout should still leave a usable Brewfile, not a zero-byte one.
    seed "$BATS_TEST_TMPDIR/no-such-repo"
    [ "$status" -eq 0 ]
    [ -s "$CHEZ_CONFIG_DIR/Brewfile.local" ]
}

# ── the apply hook reads the same overlay ────────────────────────────────────

@test "the brew-bundle hook installs from the overlay, and seeds it" {
    # Without this the overlay is half a mechanism: doctor would call an adopted
    # package declared and chez mirror would spare it, but nothing would ever
    # install it — so a Mac restored from the repo would quietly lose it.
    #
    # The hook builds its file list in the template, from render-time data. The
    # overlay's path comes from XDG_CONFIG_HOME, which a render cannot know, so
    # it is appended in bash and must be appended LAST.
    local hook="$REPO_ROOT/src/.chezmoiscripts/run_after_02-brew-bundle.sh.tmpl"
    grep -qF 'features/brew/lib/tiers.sh' "$hook"
    grep -qF 'LOCAL_BREWFILE="$(chez_local_brewfile)"' "$hook"
    grep -qF 'brew_seed_local_brewfile' "$hook"
    grep -qF 'FILES+=("$LOCAL_BREWFILE")' "$hook"
    # Appended after the array literal closes, never inside it.
    local at_close at_append
    at_close="$(grep -n '^)$' "$hook" | head -n1 | cut -d: -f1)"
    at_append="$(grep -n 'FILES+=("\$LOCAL_BREWFILE")' "$hook" | head -n1 | cut -d: -f1)"
    [ "$at_append" -gt "$at_close" ]
}

@test "the hook checks that tiers.sh loaded before calling into it" {
    # The hook runs under `set -uo pipefail`, not `-e`, so a refused source is
    # not fatal on its own — it would just leave chez_local_brewfile undefined
    # and print `command not found` on every apply. Gating on the status turns
    # that into one warning and no overlay, which is the safe reading here.
    local hook="$REPO_ROOT/src/.chezmoiscripts/run_after_02-brew-bundle.sh.tmpl"
    grep -qF 'HAVE_LOCAL_TIER=0' "$hook"
    grep -qF '[ "$HAVE_LOCAL_TIER" -eq 1 ]' "$hook"
}

# ── loading ──────────────────────────────────────────────────────────────────

@test "tiers.sh refuses to load without core/paths.sh" {
    # The dangerous degradation, so it is a refusal instead. Without paths.sh
    # there is no chez_local_brewfile, the overlay drops out of the tier set,
    # and every package adopted with `chez adopt --local` reads as undeclared —
    # which is precisely the list chez mirror offers to uninstall. Callers all
    # treat a failed load as "resolve nothing", which is the safe direction.
    local orphan="$BATS_TEST_TMPDIR/orphan/features/brew/lib"
    mkdir -p "$orphan"
    cp "$LIB" "$orphan/tiers.sh"
    run bash -c ". '$orphan/tiers.sh'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"this checkout is incomplete"* ]] || return 1
}

# ── brew_resolve_file ────────────────────────────────────────────────────────

@test "brew_resolve_file resolves a repo tier against the repo root" {
    run bash -c ". '$LIB'; brew_resolve_file '$REPO_ROOT' features/brew/Brewfile"
    [ "$status" -eq 0 ]
    [ "$output" = "$REPO_ROOT/features/brew/Brewfile" ]
}

@test "brew_resolve_file passes an absolute path through untouched" {
    overlay 'brew "ffmpeg"'
    run bash -c ". '$LIB'; brew_resolve_file '$REPO_ROOT' '$CHEZ_CONFIG_DIR/Brewfile.local'"
    [ "$status" -eq 0 ]
    [ "$output" = "$CHEZ_CONFIG_DIR/Brewfile.local" ]
}

@test "brew_resolve_file yields nothing for a file that is not there" {
    # Silence, not the path: callers append what it prints straight into the
    # tier array, and a non-existent entry would reach `grep -h` and `cat`.
    run bash -c ". '$LIB'; brew_resolve_file '$REPO_ROOT' features/brew/Brewfile.nope"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run bash -c ". '$LIB'; brew_resolve_file '$REPO_ROOT' /nowhere/Brewfile.local"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
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
    # A Brewfile may say `brew "Azure/kubelogin/kubelogin"`; brew leaves prints
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
    b=$(bf Brewfile.extra 'brew "hashicorp/tap/terraform"')
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
