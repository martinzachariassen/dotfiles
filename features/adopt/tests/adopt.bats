#!/usr/bin/env bats
# Coverage for features/adopt/cli.sh — the verb that records what this Mac
# already has, so the repo stops calling it drift.
#
# brew and chezmoi are stubbed throughout, and the repo the CLI writes to is a
# scratch copy. Every decision adopt makes is about what is installed and what
# is already declared, and neither question may be answered by the machine
# running the suite: on a Mac that happens to have ffmpeg, "an uninstalled name
# is refused" would pass or fail on nothing to do with the code. helper.bash
# pins CHEZ_CONFIG_DIR for the same reason, so no test can read — or append
# to — the runner's real overlay.

setup() {
    load '../../../core/testing/helper'
    skip_unless jq "adopt resolves the declared set through brew_active_files"

    CLI="$REPO_ROOT/features/adopt/cli.sh"
    STUB="$BATS_TEST_TMPDIR/bin"
    OVERLAY="$CHEZ_CONFIG_DIR/Brewfile.local"
    FAKE_HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$STUB" "$FAKE_HOME"

    # A scratch repo, so an appended entry never lands in the real Brewfile.
    FAKE_ROOT="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$FAKE_ROOT/features/brew/lib" "$FAKE_ROOT/core"
    cp "$REPO_ROOT/core/ui.sh" "$REPO_ROOT/core/dry-run.sh" \
        "$REPO_ROOT/core/paths.sh" "$FAKE_ROOT/core/"
    cp "$REPO_ROOT/features/brew/lib/tiers.sh" "$FAKE_ROOT/features/brew/lib/"
    cp "$REPO_ROOT/features/brew/Brewfile.local.template" "$FAKE_ROOT/features/brew/"
    BREWFILE="$FAKE_ROOT/features/brew/Brewfile"
    printf '# core\nbrew "jq"\ncask "raycast"\n' >"$BREWFILE"

    # What the stubs report. Named after the question each one answers, and set
    # per test rather than baked in, so a test's fixture reads at its top.
    STUB_FORMULAE=""
    STUB_CASKS=""
    STUB_MANAGED=""

    stub_bin "$STUB" brew '
kind=""; want=""
for a in "$@"; do
    case "$a" in
        --formula) kind=formula ;;
        --cask) kind=cask ;;
    esac
    want="$a"
done
list=""
[ "$kind" = formula ] && list="$STUB_FORMULAE"
[ "$kind" = cask ] && list="$STUB_CASKS"
for n in $list; do [ "$n" = "$want" ] && exit 0; done
exit 1'

    stub_bin "$STUB" chezmoi '
case "${1:-}" in
    data) printf "%s" "{\"brewfiles\":{\"core\":\"features/brew/Brewfile\"}}" ;;
    managed) [ -n "${STUB_MANAGED:-}" ] && printf "%s\n" "$STUB_MANAGED" ;;
    add) printf "added %s\n" "$*" ;;
esac
exit 0'
}

# adopt ARGS… — run the verb against the scratch repo with the stubs in front.
adopt() {
    run env PATH="$STUB:$PATH" HOME="$FAKE_HOME" DOTFILES_DIR="$FAKE_ROOT" \
        STUB_FORMULAE="$STUB_FORMULAE" STUB_CASKS="$STUB_CASKS" \
        STUB_MANAGED="$STUB_MANAGED" \
        bash "$CLI" "$@"
}

# lines_matching REGEX FILE — how many times FILE declares it.
lines_matching() { grep -cE "$1" "$2" 2>/dev/null || true; }

# ─── which file gets the line ────────────────────────────────────────────────

@test "an installed formula is appended to the repo Brewfile" {
    STUB_FORMULAE="ffmpeg"
    adopt ffmpeg
    [ "$status" -eq 0 ]
    grep -qx 'brew "ffmpeg"' "$BREWFILE"
}

@test "an installed cask is appended as a cask, not a formula" {
    # Formulae and casks are separate Homebrew namespaces. Writing brew "obs"
    # for an installed cask leaves the cask untracked forever AND declares a
    # formula nothing has installed, so the next bundle run tries to fetch it.
    STUB_CASKS="obs"
    adopt obs
    [ "$status" -eq 0 ]
    grep -qx 'cask "obs"' "$BREWFILE"
}

@test "--local writes to the overlay and leaves the repo Brewfile alone" {
    STUB_FORMULAE="ffmpeg"
    before="$(cat "$BREWFILE")"
    adopt --local ffmpeg
    [ "$status" -eq 0 ]
    grep -qx 'brew "ffmpeg"' "$OVERLAY"
    [ "$before" = "$(cat "$BREWFILE")" ]
}

@test "several packages are adopted in one run" {
    STUB_FORMULAE="ffmpeg htop"
    adopt ffmpeg htop
    [ "$status" -eq 0 ]
    grep -qx 'brew "ffmpeg"' "$BREWFILE"
    grep -qx 'brew "htop"' "$BREWFILE"
}

# ─── what adopt refuses ──────────────────────────────────────────────────────

@test "an uninstalled name is refused and writes nothing" {
    # Adopt captures reality; it does not place orders. Accepting a name nothing
    # has installed lets a typo into the repo Brewfile, where it breaks
    # brew bundle install on every OTHER machine and not on this one.
    STUB_FORMULAE="ffmpeg"
    before="$(cat "$BREWFILE")"
    adopt no-such-package
    [ "$status" -eq 1 ]
    [[ "$output" == *"not installed"* ]] || return 1
    [ "$before" = "$(cat "$BREWFILE")" ]
}

@test "a name installed as both is refused until the kind is given" {
    # docker is the live example. Guessing would declare one namespace and leave
    # the other permanently untracked.
    STUB_FORMULAE="docker"
    STUB_CASKS="docker"
    adopt docker
    [ "$status" -eq 1 ]
    [[ "$output" == *"BOTH"* ]] || return 1
    no_match '"docker"' "$BREWFILE"

    adopt --cask docker
    [ "$status" -eq 0 ]
    grep -qx 'cask "docker"' "$BREWFILE"
}

@test "one refusal does not cost the valid names, and the run still fails" {
    # Exit status is what a script branches on, so a partial success must not
    # report 0 — but a typo in one argument should not discard the others.
    STUB_FORMULAE="ffmpeg"
    adopt no-such-package ffmpeg
    [ "$status" -eq 1 ]
    grep -qx 'brew "ffmpeg"' "$BREWFILE"
}

# ─── adopting twice ──────────────────────────────────────────────────────────

@test "adopting something already declared is a no-op" {
    # `brew bundle add` appends unconditionally; two brew "jq" lines in one
    # Brewfile is drift that looks like configuration.
    STUB_FORMULAE="jq"
    adopt jq
    [ "$status" -eq 0 ]
    # Named in full: the closing summary also contains the words "already
    # declared", so a bare substring match would pass on any run at all.
    [[ "$output" == *"jq is already declared in features/brew/Brewfile"* ]] || return 1
    [ "$(lines_matching '^brew "jq"$' "$BREWFILE")" -eq 1 ]
}

@test "adopting twice in a row writes exactly one line" {
    STUB_FORMULAE="ffmpeg"
    adopt ffmpeg
    adopt ffmpeg
    [ "$status" -eq 0 ]
    [ "$(lines_matching '^brew "ffmpeg"$' "$BREWFILE")" -eq 1 ]
}

@test "a tap-qualified declaration counts as declared" {
    # The comparison is the bare lowercased name, matching brew_bare_names: a
    # Brewfile may qualify a tap formula and `brew list` never does, and tap
    # owners carry capitals the installed name drops.
    printf 'brew "Azure/kubelogin/kubelogin"\n' >>"$BREWFILE"
    STUB_FORMULAE="kubelogin"
    adopt kubelogin
    [ "$status" -eq 0 ]
    [[ "$output" == *"kubelogin is already declared"* ]] || return 1
}

@test "a formula does not count as declared because a cask shares its name" {
    # The declared-check is per namespace, like the install is.
    printf 'cask "docker"\n' >>"$BREWFILE"
    STUB_FORMULAE="docker"
    adopt docker
    [ "$status" -eq 0 ]
    grep -qx 'brew "docker"' "$BREWFILE"
}

@test "an unresolvable tier set still adopts, rather than erroring out" {
    # adopt only ever ADDS, so a tier set it could not resolve costs at worst a
    # duplicate warning it did not print — nothing is uninstalled either way.
    # This is also the empty-array case: bash 3.2 expands "${arr[@]}" on an
    # empty array as unbound under `set -u`, and a Mac runs /bin/bash 3.2 until
    # Homebrew's bash exists — precisely when chezmoi and jq may not either.
    stub_bin "$STUB" chezmoi 'printf "{}"; exit 0'
    STUB_FORMULAE="ffmpeg"
    adopt ffmpeg
    [ "$status" -eq 0 ]
    [[ "$output" != *"unbound variable"* ]] || return 1
    grep -qx 'brew "ffmpeg"' "$BREWFILE"
}

# ─── the machine-local overlay ───────────────────────────────────────────────

@test "the overlay is seeded from the shipped template, not invented" {
    # So the prose explaining the file lives in exactly one place, and a
    # generated overlay reads the same as a hand-written one.
    STUB_FORMULAE="ffmpeg"
    adopt --local ffmpeg
    grep -q 'packages THIS Mac keeps' "$OVERLAY"
}

@test "an overlay entry makes the package declared everywhere" {
    # The whole mechanism in one assertion: once adopted locally the package
    # resolves as declared, so doctor stops reporting it and the removal verbs
    # never offer it.
    STUB_FORMULAE="ffmpeg"
    adopt --local ffmpeg
    adopt ffmpeg
    [ "$status" -eq 0 ]
    [[ "$output" == *"ffmpeg is already declared in"* ]] || return 1
    no_match '^brew "ffmpeg"$' "$BREWFILE"
}

@test "deleting the overlay line hands the package back" {
    # The round trip that makes divergence reversible rather than permanent.
    STUB_FORMULAE="ffmpeg"
    adopt --local ffmpeg
    grep -v '^brew "ffmpeg"$' "$OVERLAY" >"$OVERLAY.tmp"
    mv "$OVERLAY.tmp" "$OVERLAY"

    adopt --local ffmpeg
    [ "$status" -eq 0 ]
    [[ "$output" == *"adopted 1, already declared 0"* ]] || return 1
    [ "$(lines_matching '^brew "ffmpeg"$' "$OVERLAY")" -eq 1 ]
}

# ─── dry run ─────────────────────────────────────────────────────────────────

@test "--dry-run writes nothing, not even the overlay" {
    STUB_FORMULAE="ffmpeg"
    before="$(cat "$BREWFILE")"
    adopt --dry-run ffmpeg
    [ "$status" -eq 0 ]
    [ "$before" = "$(cat "$BREWFILE")" ]

    adopt --dry-run --local ffmpeg
    [ "$status" -eq 0 ]
    [ ! -f "$OVERLAY" ]
}

# ─── paths versus packages ───────────────────────────────────────────────────

@test "an argument that exists on disk goes to chezmoi, not to the Brewfile" {
    touch "$FAKE_HOME/.foorc"
    before="$(cat "$BREWFILE")"
    adopt "$FAKE_HOME/.foorc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"chezmoi"* ]] || return 1
    [ "$before" = "$(cat "$BREWFILE")" ]
}

@test "a path chezmoi already manages is a no-op" {
    touch "$FAKE_HOME/.foorc"
    STUB_MANAGED=".foorc"
    adopt "$FAKE_HOME/.foorc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already managed"* ]] || return 1
}

@test "a tap-qualified package name is not mistaken for a path" {
    # It contains slashes, so the slash cannot be the test — existence is.
    STUB_FORMULAE="kubelogin"
    adopt azure/kubelogin/kubelogin
    [ "$status" -eq 0 ]
    grep -qx 'brew "azure/kubelogin/kubelogin"' "$BREWFILE"
}

# ─── argument handling ───────────────────────────────────────────────────────

@test "no arguments prints usage and exits 2" {
    adopt
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage: chez adopt"* ]] || return 1
}

@test "an unknown flag is refused rather than adopted as a package" {
    STUB_FORMULAE="ffmpeg"
    adopt --nope ffmpeg
    [ "$status" -eq 2 ]
    no_match 'nope' "$BREWFILE"
}

@test "-- ends the flags, so a file named like one can still be adopted" {
    touch "$FAKE_HOME/--weird"
    adopt -- "$FAKE_HOME/--weird"
    [ "$status" -eq 0 ]
    [[ "$output" == *"chezmoi"* ]] || return 1
}

@test "--help exits 0 and names both targets" {
    adopt --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--local"* ]] || return 1
    [[ "$output" == *"<path>"* ]] || return 1
}
